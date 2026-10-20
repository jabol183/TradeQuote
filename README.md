# TradeQuote AI

Native, local-first SwiftUI quotation app for tradespeople. Capture job photos, dictate scope, review AI-extracted lines, apply **your own** saved labour/material rates, approve pricing and produce an A4 PDF.

## Open on iPad
Open **TradeQuote.swiftpm** in Swift Playgrounds on an Apple Intelligence-compatible iPad with iPadOS 26 or later. Foundation Models generation requires supported hardware, enabled Apple Intelligence and a downloaded model. The app remains usable for manual quotes without the model.

## Xcode
Open `TradeQuote.swiftpm` in current Xcode on macOS. Select the TradeQuote iOS application scheme. No external libraries or API keys. For iOS 27+ the image understanding path uses multimodal Foundation Models; earlier compatible systems can still use voice-to-text and manual photo descriptions.

## Build an installable app with GitHub Actions
Every push runs `.github/workflows/build-ios.yml` on a macOS runner:
1. runs the quote-logic tests (`swift test`);
2. generates an Xcode project from `BuildSupport/project.yml` (XcodeGen) using the same sources as `TradeQuote.swiftpm`;
3. archives the app without code signing and uploads **TradeQuote-unsigned.ipa** as a run artifact (Actions tab → the run → *Artifacts*).

Pushing a tag such as `v1.0.0` also attaches the `.ipa` to a GitHub Release.

The `.ipa` is unsigned. Install it with a tool that signs with your own Apple ID, such as Sideloadly or AltStore. A free Apple ID signature lasts 7 days.

**TestFlight:** the separate *TestFlight* workflow signs the app and uploads it to App Store Connect. One-time setup is in [TESTFLIGHT.md](TESTFLIGHT.md).

## Keyboard not appearing in Swift Playgrounds
Swift Playgrounds on iPad has a known bug where tapping a text field shows a cursor but no on-screen keyboard (and sometimes ignores a hardware keyboard). It affects the Playgrounds preview, not the app. Workarounds: disconnect/reconnect a hardware keyboard, turn off Predictive text in iPad Settings → General → Keyboard, or install the CI-built `.ipa`.

## Run portable business-logic tests
From the repository root: `swift test` (Swift 6). The root Package.swift exposes the **same QuoteCore source code** used by the iOS app.

## Rules
- AI-created content is never marked reviewed, assigned a rate, or converted directly to a final quote.
- Every line has a source (voice/photo/manual), editable quantity, specification, and independent confirmation.
- `Needs confirmation` blocks review; `Rate not set` blocks pricing.
- A contractor approves review, then rates, then generates a final PDF. Every quote retains frozen approved unit prices.
- Money uses Decimal and 2-decimal rounding; model output never calculates price or VAT.
- Source photographs and data stay in the application's Documents directory. No cloud account, tracking, auto-emailing or background upload.
- Sending uses the system share sheet; sent/accepted/declined are recorded manually, not inferred from sharing.
- No illustrative prices are preloaded. The contractor must set rates, VAT and business identity.

## Permissions
Camera, photo library, microphone, and Speech Recognition permission strings are supplied in the app manifest. Dictation insists on on-device speech recognition. Availability and permissions are reported rather than silently falling back to cloud.

## App architecture
- `QuoteCore` — Foundation-only Codable data and deterministic pricing / approval validation.
- `AppModule` — SwiftUI views, local JSON storage, photos, on-device speech and Foundation Models, PDF renderer, and Siri/App Shortcuts new-quote capture.
- `Tests` — pure Swift quote arithmetic and gating tests.

## Verification caveat
`swift test` checks business rules. The GitHub Actions workflow compiles the full iOS app; behaviour on a real device (camera, dictation, Foundation Models) still needs testing on hardware.


## Swift Playgrounds compatibility (iPadOS 26/27)

- `Attachment` is an image-prompting symbol introduced with the **iOS/iPadOS 27 Foundation Models SDK**. Swift Playgrounds built with the older SDK does not recognize the symbol even inside an `#available` check.
- The image-attachment code is compiled only by Swift 6.4+ toolchains and is further guarded at runtime for iOS/iPadOS 27+. **Older toolchains keep photo capture, manually reviewing photos, speech-to-text, Foundation Models text extraction, pricing and PDF generation.** They display an informative message instead of analyzing image pixels.
- `CaptureTile` uses an explicit `nonisolated` data-only initializer for the PhotosPicker label closure to resolve the Swift 6 actor isolation warning.
