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
    @State private var proposal: DraftProposal?
    @State private var photoEditing: PhotoContext?
    @State private var transcribing = false
    @AppStorage("TradeQuote.SpeechLocale") private var speechLocale = "en_GB"
    private var vocabulary: [String] { store.recipes.map(\.name) + store.rates.map(\.name) }


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
                                Button {
                                    photoEditing = store.quote(quoteID)?.photoContexts?.first(where: { $0.filename == filename }) ?? PhotoContext(filename: filename)
                                } label: { PhotoThumb(filename: filename) }
                                    .buttonStyle(.plain)
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
                                            transcribing = true
                                            defer { transcribing = false }
                                            let result = try await voice.stopAndTranscribe(locale: speechLocale, vocabulary: vocabulary)
                                            store.editQuote(quoteID) { $0.voiceTranscripts = ($0.voiceTranscripts ?? []) + [result] }
                                            // onChange(of: noteText) saves this to the quote.
                                            noteText = [noteText, result].filter { !$0.isEmpty }.joined(separator: "\n")
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

                    Picker("Dictation language", selection: $speechLocale) {
                        Text("English (UK)").tag("en_GB")
                        Text("English (US)").tag("en_US")
                        Text("Polski").tag("pl_PL")
                        Text("Deutsch").tag("de_DE")
                    }
                    Text("Requires an installed on-device speech model. Check highlighted quantities in the draft.")
                        .font(.caption).foregroundStyle(.secondary)
                    if transcribing { ProgressView("Transcribing on device…") }
                    if voice.hasRetryRecording && !transcribing {
                        Button("Retry retained recording") {
                            Task {
                                transcribing = true
                                defer { transcribing = false }
                                do {
                                    let result = try await voice.retryTranscription(locale: speechLocale, vocabulary: vocabulary)
                                    store.editQuote(quoteID) { $0.voiceTranscripts = ($0.voiceTranscripts ?? []) + [result] }
                                    noteText = [noteText, result].filter { !$0.isEmpty }.joined(separator: "\n")
                                } catch { report(error) }
                            }
                        }
                        Button("Discard recording", role: .destructive) { voice.cancel() }
                    }
                    Text("Job notes / transcript").font(.subheadline.weight(.semibold))
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                        .onChange(of: noteText) { _, value in
                            // Only a real edit counts; loading the saved notes must not reset approvals.
                            guard store.quote(quoteID)?.notes != value else { return }
                            store.editQuote(quoteID, scopeChanged: true) { $0.notes = value }
                        }
                    Text("Describe the whole job naturally. Example: Two sockets in the kitchen, one switch in the living room. Replace all; parts provided by customer. Check the proposed items before applying.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if processing {
                    ProgressView(processingMessage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                ActionButton(title: "Organise draft with on-device AI", icon: "sparkles", disabled: processing || transcribing || voice.isRecording, action: {
                    UIApplication.shared.dismissKeyboard()
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
        .disabled(processing || transcribing)
        .sheet(item: $proposal) { draft in
            DraftProposalView(proposal: draft, quoteID: quoteID) { changes, observations in
                store.apply(changes, observations: observations, to: quoteID)
                proposal = nil
                next()
            }
        }
        .sheet(item: $photoEditing) { context in
            PhotoEvidenceEditor(context: context, quoteID: quoteID)
        }
        .keyboardDoneButton()
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
            guard !items.isEmpty else { return }
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
        var changes: [DraftChange] = []
        var observations: [PhotoObservation] = []
        var warnings: [String] = []
        if !quote.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            processingMessage = "Extracting supported facts and matching your jobs…"
            do {
                let result = try await DraftAI.extractVoice(quote.notes, source: .note, recipes: store.recipes, existing: quote.lines)
                changes = result.changes.map { change in
                    var change = change
                    if (quote.voiceTranscripts ?? []).contains(where: { $0.contains(change.line.sourceDetail) }) { change.line.source = .voice }
                    return change
                }
                warnings += result.warnings
            } catch { warnings.append(error.localizedDescription) }
        }
        for filename in quote.photoNames {
            processingMessage = "Recording photo observations…"
            guard let image = store.photo(named: filename) else { warnings.append("A source photo could not be opened."); continue }
            let context = quote.photoContexts?.first(where: { $0.filename == filename }) ?? PhotoContext(filename: filename)
            do { observations += try await DraftAI.extractPhoto(image, context: context, notes: quote.notes) }
            catch { warnings.append(error.localizedDescription); if error is DraftAI.Failure { break } }
        }
        guard store.quote(quoteID)?.notes == quote.notes, store.quote(quoteID)?.photoNames == quote.photoNames else {
            warnings.append("The job changed during analysis. Run analysis again against the current evidence.")
            report(AnalysisFailure.changed)
            return
        }
        if changes.isEmpty && observations.isEmpty {
            error = (["No new supported changes. Existing items have been preserved. Add a recipe or edit items in Review."] + warnings).joined(separator: "\n")
            showError = true
        } else {
            proposal = DraftProposal(changes: changes, observations: observations, warnings: Array(Set(warnings)).sorted())
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


private enum AnalysisFailure: LocalizedError {
    case changed
    var errorDescription: String? { "The job changed during analysis. Run it again against the current evidence." }
}
