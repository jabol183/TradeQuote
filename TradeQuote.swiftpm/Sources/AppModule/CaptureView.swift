import SwiftUI
import PhotosUI
import UIKit
import QuoteCore

struct CaptureView: View {
    @Environment(TradeQuoteStore.self) private var store
    let quoteID: UUID
    let next: () -> Void

    @State private var noteText = ""
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var voice = VoiceCapture()
    @State private var processing = false
    @State private var processingMessage = ""
    @State private var error: String?
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Heading(text: "Capture the job")
                Text("Photograph the work and describe it naturally. Your notes and photos stay on your device.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button { showCamera = true } label: {
                        CaptureTile(title: "Take Photos", symbol: "camera.fill", subtitle: "Use camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 6, matching: .images) {
                        CaptureTile(title: "Photo Library", symbol: "photo.on.rectangle", subtitle: "Choose photos")
                    }
                }
                .buttonStyle(.plain)

                if let quote = store.quote(quoteID), !quote.photoNames.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(quote.photoNames, id: \.self) { filename in
                                PhotoThumb(filename: filename)
                                    .contextMenu {
                                        Button("Remove photo", role: .destructive) {
                                            store.removePhoto(filename, from: quoteID)
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Heading(text: "Dictate job")
                    ZStack {
                        RoundedRectangle(cornerRadius: 17)
                            .fill(Theme.blue.opacity(0.045))
                        VStack(spacing: 15) {
                            Image(systemName: voice.isRecording ? "waveform" : "waveform.circle.fill")
                                .font(.system(size: 52))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(voice.isRecording ? .red : Theme.blue)
                                .symbolEffect(.variableColor.iterative, isActive: voice.isRecording)
                            Text(voice.isRecording ? "Recording \(String(format: "%02d:%02d", voice.recordingSeconds / 60, voice.recordingSeconds % 60))" : "Speak naturally")
                                .font(.callout.weight(.medium))
                            Button {
                                Task {
                                    if voice.isRecording {
                                        do {
                                            let result = try await voice.stopAndTranscribe()
                                            noteText = [noteText, result].filter { !$0.isEmpty }.joined(separator: "\n")
                                            store.editQuote(quoteID, scopeChanged: true) { $0.notes = noteText }
                                        } catch { report(error) }
                                    } else {
                                        do { try await voice.begin() }
                                        catch { report(error) }
                                    }
                                }
                            } label: {
                                Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 62, height: 62)
                                    .background(voice.isRecording ? .red : Theme.blue, in: Circle())
                            }
                            .accessibilityLabel(voice.isRecording ? "Stop recording" : "Start dictation")
                        }.padding(20)
                    }
                    .frame(height: 205)

                    Text("Job notes / transcript").font(.subheadline.weight(.semibold))
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                        .onChange(of: noteText) { _, value in
                            store.editQuote(quoteID, scopeChanged: true) { $0.notes = value }
                        }
                    Text("Example: Replace six sockets, install two light fittings, approximately four hours.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if processing {
                    ProgressView(processingMessage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                ActionButton(title: "Organise draft with on-device AI", icon: "sparkles", disabled: processing || voice.isRecording, action: {
                    Task { await organiseDraft() }
                })
                Button("Continue with manual review", action: next)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Text("The AI does not approve items or assign prices. Every suggestion must be reviewed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .background(Theme.bg)
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                do { try store.addPhoto(image, to: quoteID) }
                catch { report(error) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickedPhotos) { _, items in
            Task {
                for item in items {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else { continue }
                        try store.addPhoto(image, to: quoteID)
                    } catch { report(error) }
                }
                pickedPhotos = []
            }
        }
        .onAppear { noteText = store.quote(quoteID)?.notes ?? "" }
        .onDisappear { voice.cancel() }
        .alert("Unable to complete action", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "Unknown error") }
    }

    private func report(_ err: Error) {
        error = err.localizedDescription
        showError = true
    }

    private func organiseDraft() async {
        guard let quote = store.quote(quoteID) else { return }
        guard !quote.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !quote.photoNames.isEmpty else {
            error = "Add a photo or describe the job first."
            showError = true
            return
        }
        processing = true
        defer { processing = false }
        var produced: [QuoteLine] = []
        var newTitle: String?
        var errors: [String] = []
        if !quote.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            processingMessage = "Organising dictation…"
            do {
                let (title, items) = try await DraftAI.extractVoice(quote.notes)
                produced.append(contentsOf: items)
                newTitle = title
            } catch { errors.append("Voice: \(error.localizedDescription)") }
        }
        for filename in quote.photoNames.prefix(6) {
            processingMessage = "Reviewing photo…"
            guard let image = store.photo(named: filename) else { continue }
            do { produced.append(contentsOf: try await DraftAI.extractPhoto(image, filename: filename)) }
            catch { errors.append("Photo: \(error.localizedDescription)") }
        }
        store.editQuote(quoteID, scopeChanged: true) { draft in
            if let newTitle, !newTitle.isEmpty { draft.title = newTitle }
            for line in produced {
                // Re-analysis is idempotent for identical suggestions; no approved item is overwritten.
                if !draft.lines.contains(where: {
                    $0.title.caseInsensitiveCompare(line.title) == .orderedSame &&
                    $0.source == line.source && $0.sourceDetail == line.sourceDetail
                }) { draft.lines.append(line) }
            }
        }
        if !errors.isEmpty {
            error = errors.joined(separator: "\n")
            showError = true
        }
        if !produced.isEmpty { next() }
        else if errors.isEmpty {
            error = "No work items could be evidenced. Add them manually in Review."
            showError = true
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

private struct CaptureTile: View {
    let title: String
    let symbol: String
    let subtitle: String

    // PhotosPicker's label builder is @Sendable and not MainActor-isolated.
    // This initializer stores immutable String values and never touches UI state.
    nonisolated init(title: String, symbol: String, subtitle: String) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(Theme.blue)
            Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Theme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}
