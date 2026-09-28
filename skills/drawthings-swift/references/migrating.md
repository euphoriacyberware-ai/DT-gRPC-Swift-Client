# Code written for older versions

Models often produce DrawThingsClient 1.x code, or code for the separate DrawThingsQueue,
DrawThingsVideoKit and DrawThingsKit packages. None of it compiles against 2.x. Replace it:

| Old (doesn't exist in 2.x) | 2.x |
|---|---|
| `.package(url: ".../DT-gRPC-Swift-Client", ...)`, `branch: "main"` | `.package(url: ".../DrawThings-Swift", from: "2.1.0")`, products from package `DrawThings-Swift` |
| `DrawThingsClient` class, `@StateObject var client` | `DrawThingsSession`, `@State var session` |
| `DrawThingsService(address:useTLS:)` | `DrawThingsService(address:options: ConnectionOptions(security: .tls() / .plaintext))` |
| `echo(sharedSecret:)`, per-call `sharedSecret:` | `ConnectionOptions(sharedSecret:)`; `echo()` |
| `generateImage(prompt:configuration: Data, ... progressHandler:previewHandler:audioHandler:)` | `service.stream(GenerationRequest)` or `service.generate(GenerationRequest)` |
| `config.toFlatBufferData()` + `imageToDTTensor` before sending | Pass `DrawThingsConfiguration` and `CGImage`s in `GenerationRequest`; the client encodes |
| `ImageGenerationProgress`, `currentProgress` | `GenerationProgress` value (`stage`, `step`, `totalSteps`, `fractionCompleted`) |
| `GenerationOutput`, `generateImageAndAudio` | `GenerationResult` (`images`, `audio`, `media`) |
| `seed: Int64`, `seedMode: Int32` | `seed: UInt32?`, `seedMode: SeedMode` |
| `LatentModelFamily` | `ModelFamily` |
| `ModelSpecProvider` | `service.modelSpecs.register(_:)` |
| `HintBuilder().addPose(...).build()` (chained class) | `var b = HintBuilder(); b.addPose(...); try b.build()` |
| `DrawThingsQueue(address:useTLS:)` class, `JobQueue`, `GenerationJob` | `GenerationQueue(service:storage:)`, `QueueJob` |
| Queue's own `GenerationRequest` (PlatformImage, `name`) / `GenerationResult` (`audioData`) | Client's `GenerationRequest` (CGImage) with `enqueue(_:name:)`; `result.audio` |
| `queue.events` Combine publisher, `JobEvent` | `queue.events` `AsyncStream<QueueEvent>` |
| `pendingRequests`, `completedResults`, `errors`, `status(for:)` | `pending`, `finished`, `job(_:)?.status` |
| `modelFamilyProvider`, `audioSampleRateProvider` | `GenerationRequest.modelFamily` / `audioSampleRate` when needed |
| `VideoProcessor.connect(to: DrawThingsQueue)`, Combine `events` | `connect(to: queue.results)` or `ingest(_:)`; `AsyncStream` events |
| `numFrames > 1` to detect video, `nativeFrameRate ?? 16` | `result.media.isVideo`, `result.media.frameRate` |
| Kit's `ConfigurationCodable`, `ConfigurationJSON` | `DrawThingsConfiguration.fromJSON`/`toJSON`/`mergeJSON` |
| Kit's `copyToClipboard()` / `pasteFromClipboard()` | `exportToJSON()` / `loadFromJSON(_:)` with the pasteboard in the app |
| `latentModelFamily(forFile:)` | `modelFamily(forFile:)` |
| Kit, Queue or VideoKit SwiftUI views (`QueueView`, `ServerProfilesView`, `VideoConfigurationView`...) | Removed; build views (see `swiftui.md` and `Examples/DrawThingsExample`) |

The package's `MIGRATING-2.0.md` has the complete mapping. An app can't mix the old Queue,
VideoKit or Kit packages (which require the 1.x client) with DrawThings-Swift 2.x.
