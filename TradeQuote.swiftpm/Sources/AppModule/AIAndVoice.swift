import Foundation
import FoundationModels
import AVFoundation
import Speech
import UIKit
import Observation
import QuoteCore

@Generable
struct ExtractionDraft {
    @Guide(description: "A short factual title based only on the supplied evidence")
    var title: String
    @Guide(description: "Requested work items explicitly supported by supplied input; omit unsupported guesses")
    var items: [ExtractedWork]
}

@Generable
struct ExtractedWork {
    @Guide(description: "Short action and object. Do not add unspecified materials or prices.")
    var title: String
    @Guide(description: "Explicit count or hours only; nil if not clearly evidenced")
    var quantity: Double?
    @Guide(description: "Unit such as each or h")
    var unit: String
    @Guide(description: "labour or materials")
    var category: String
    @Guide(description: "Missing specification or uncertainty; empty if fully explicit")
    var needsConfirmation: String
}

enum DraftAI {
    enum Failure: LocalizedError {
        case unavailable, photoNeedsNewerOS
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple's on-device model is unavailable. Enable Apple Intelligence or add items manually."
            case .photoNeedsNewerOS: return "Photo understanding needs the iOS/iPadOS 27 Foundation Models image API. You can still attach and inspect photos."
            }
        }
    }

    static func extractVoice(_ transcript: String) async throws -> (String, [QuoteLine]) {
        guard case .available = SystemLanguageModel.default.availability else { throw Failure.unavailable }
        let session = LanguageModelSession(instructions: """
            You are a conservative UK trade quotation assistant.
            Extract only work and exact quantities plainly spoken in the input.
            Never invent parts, lengths, time, count, material type, rate, price, certification or labour.
            Mark incomplete material specifications and ambiguous quantities with a concise question.
            The output is an UNAPPROVED draft; every item is individually reviewed by a contractor.
            """)
        let response = try await session.respond(to: "Contractor dictation:\n\(transcript)", generating: ExtractionDraft.self)
        return (response.content.title, map(response.content.items, source: .voice, evidence: transcript))
    }

    static func extractPhoto(_ image: UIImage, filename: String) async throws -> [QuoteLine] {
        // Image attachments were added in the iOS 27 SDK (Swift compiler 6.4).
        // #available alone is not sufficient: older Playgrounds SDKs cannot even
        // resolve the Attachment symbol during compilation.
        #if compiler(>=6.4)
        guard #available(iOS 27.0, *) else { throw Failure.photoNeedsNewerOS }
        guard case .available = SystemLanguageModel.default.availability else { throw Failure.unavailable }
        guard let cgImage = image.cgImage else { throw Failure.unavailable }
        let session = LanguageModelSession(instructions: """
            Observe the attached worksite photograph cautiously.
            A photograph alone does not constitute an instruction to install, repair or replace something.
            Generate a draft line only for an unambiguous visible issue; otherwise return zero lines.
            Do not infer concealed work, number of fittings in other rooms, labour duration,
            product model, compatible materials, dimensions or price.
            Any visually observed issue requires contractor confirmation.
            """)
        let response = try await session.respond(generating: ExtractionDraft.self) {
            "Examine this worksite photo. Return observations only, never a finished quote."
            Attachment(cgImage).label(filename)
        }
        return map(response.content.items, source: .photo, evidence: filename)
        #else
        // Voice/text extraction and manual photo review remain available.
        throw Failure.photoNeedsNewerOS
        #endif
    }

    private static func map(_ items: [ExtractedWork], source: EvidenceSource, evidence: String) -> [QuoteLine] {
        items.prefix(25).compactMap { item in
            let name = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let value: Decimal? = item.quantity.flatMap { qty in
                qty.isFinite && qty > 0 && qty <= 10000 ? Decimal(qty) : nil
            }
            let uncertainty = item.needsConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = source == .photo ? (uncertainty.isEmpty ? "Confirm requested work and material specification from the site." : uncertainty)
            : (uncertainty.isEmpty ? nil : uncertainty)
            return QuoteLine(title: name,
                category: item.category.lowercased() == "materials" ? .materials : .labour,
                source: source, sourceDetail: String(evidence.prefix(250)),
                quantity: value, unit: item.unit.isEmpty ? "each" : item.unit,
                confirmationPrompt: prompt)
        }
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func once(_ completion: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        completion()
    }
}

@MainActor @Observable
final class VoiceCapture {
    var isRecording = false
    var recordingSeconds: Int = 0
    private var recorder: AVAudioRecorder?
    private var ticking: Timer?
    private var fileURL: URL?

    func begin() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { throw VoiceError.microphoneDenied }
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        guard recorder.record() else { throw VoiceError.recordingFailed }
        self.recorder = recorder
        fileURL = url
        recordingSeconds = 0
        isRecording = true
        ticking = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingSeconds += 1 }
        }
    }

    func cancel() {
        recorder?.stop()
        isRecording = false
        ticking?.invalidate()
        ticking = nil
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func stopAndTranscribe() async throws -> String {
        guard isRecording, let url = fileURL else { throw VoiceError.recordingFailed }
        recorder?.stop()
        isRecording = false
        ticking?.invalidate()
        recorder = nil
        defer { try? FileManager.default.removeItem(at: url) }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard authorized else { throw VoiceError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_GB")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw VoiceError.onDeviceUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let transcript = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let gate = CompletionGate()
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let error { gate.once { continuation.resume(throwing: error) } }
                else if let result, result.isFinal {
                    gate.once { continuation.resume(returning: result.bestTranscription.formattedString) }
                }
            }
        }
        return transcript
    }

    enum VoiceError: LocalizedError {
        case microphoneDenied, speechDenied, onDeviceUnavailable, recordingFailed
        var errorDescription: String? {
            switch self {
            case .microphoneDenied: return "Microphone access is required for dictation."
            case .speechDenied: return "Speech recognition permission was not granted."
            case .onDeviceUnavailable: return "On-device English (UK) speech recognition is unavailable. Type your notes instead."
            case .recordingFailed: return "Audio recording could not start."
            }
        }
    }
}
