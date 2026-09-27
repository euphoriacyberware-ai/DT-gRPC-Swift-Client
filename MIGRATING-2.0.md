# Migrating to DrawThingsClient 2.0

Version 2 moves to Swift 6, grpc-swift 2 and an event-stream API, and fixes a set of bugs that
could lose audio, show stale progress, crash on bad values or send rotated images. Most changes
are mechanical; this guide maps the 1.x API to 2.0.

## Requirements

| | 1.x | 2.0 |
|---|---|---|
| Platforms | macOS 14 / iOS 17 | **macOS 15 / iOS 18** |
| Swift | 5.9 | **6.0** (Xcode 16) |
| gRPC | grpc-swift 1.x | grpc-swift 2 |
| Package pin | `branch: "main"` (1.6–1.7.1 couldn't be pinned by version) | `from: "2.0.0"` |

Stay on `.upToNextMajor(from: "1.7.2")` until you can meet the new platform floor.

## Products

The SwiftUI wrapper moved to its own product so the core module no longer imports SwiftUI or
Combine:

```swift
.product(name: "DrawThingsClient", package: "DT-gRPC-Swift-Client"),
.product(name: "DrawThingsClientUI", package: "DT-gRPC-Swift-Client"),  // for DrawThingsSession
```

## SwiftUI: `DrawThingsClient` → `DrawThingsSession`

| 1.x | 2.0 |
|---|---|
| `DrawThingsClient` (`ObservableObject`) | `DrawThingsSession` (`@Observable`, `import DrawThingsClientUI`) |
| `@StateObject var client` | `@State var session` |
| `init(address:useTLS:)` | `init(address:options:)` |
| `connect(sharedSecret:)` | `connect()`; the secret is in `ConnectionOptions` |
| `currentProgress: ImageGenerationProgress?` (a class whose changes views didn't see) | `progress: GenerationProgress?` (a value; views update on every step) |
| (previews not exposed) | `preview: CGImage?`, `previewImage` |
| `generateImage(prompt:…) -> [PlatformImage]` | `generate(_:) -> GenerationResult` (`.images`, `.platformImages`) or `generate(prompt:configuration:image:mask:hints:)` |
| `generateImageAndAudio(…) -> GenerationOutput` | `generate(_:)`; audio is `result.audio: [GeneratedAudio]` (`pcmBuffer()`, `wavData()`) |
| | `isGenerating`, `serverInfo`, `lastResult`, `cancel()` |

The class shared its name with the module, which prevented writing `DrawThingsClient.SomeType`;
that works now.

## `DrawThingsService`

### Creating and connecting

```swift
// 1.x
let service = try DrawThingsService(address: "host:7859", useTLS: true)
_ = try await service.echo(sharedSecret: "secret")

// 2.0
let service = try DrawThingsService(address: "host:7859", options: ConnectionOptions(
    security: .tls(),            // .plaintext for useTLS: false
    sharedSecret: "secret"
))
try await service.echo()
await service.shutdown()         // new: closes the connection
```

- The shared secret is set once in `ConnectionOptions`, not per call.
- IPv6 addresses (`[fe80::1]:7859`, `::1`) now parse; `ServerEndpoint` does the parsing.
- **TLS now verifies public servers.** 1.x never verified certificates. The default
  `.tls(verification: .automatic)` still accepts Draw Things' self-signed certificate on local
  networks (including host names that resolve to LAN addresses). For a self-signed server reached
  over the internet use `.tls(verification: .trustRoots([pem]))`, or `.none` to keep the 1.x
  behavior.

### Generating

`generateImage(prompt:…configuration: Data…progressHandler:previewHandler:audioHandler:) -> [Data]`
is replaced by a request value and an event stream:

```swift
// 1.x
let configData = try config.toFlatBufferData()
let imageData = try ImageHelpers.imageToDTTensor(input, forceRGB: true)
let tensors = try await service.generateImage(
    prompt: "…", configuration: configData, image: imageData,
    progressHandler: { signpost in … }, previewHandler: { data in … }, audioHandler: { data in … }
)
let images = try tensors.map { try ImageHelpers.dtTensorToImage($0, modelFamily: family) }

// 2.0
let request = GenerationRequest(prompt: "…", configuration: config, image: input)  // CGImage
for try await event in service.stream(request) {
    switch event {
    case .progress(let progress): …   // GenerationProgress (stage, step, totalSteps, fractionCompleted)
    case .preview(let image): …       // CGImage, already decoded with the right model family
    case .audio(let audio): …         // GeneratedAudio
    case .image, .remoteDownload: break
    case .completed(let result): …    // GenerationResult: images, audio, media, request
    }
}
// or: let result = try await service.generate(request)
```

- Encoding the configuration, input image and mask is done for you, off the main actor. The mask
  is encoded in Draw Things' mask format; 1.x README examples that sent a mask through
  `imageToDTTensor` crash the server.
- Events are delivered in server order and `.completed` is always last. In 1.x, handlers ran in
  unordered tasks and audio could be missing from the result.
- Cancelling the consuming task cancels the generation on the server.
- A generation that returns no image now throws `DrawThingsError.incompleteResponse`.
- `contents` and `scaleFactor` are no longer parameters.

### Model metadata

`ModelSpecProvider` is replaced by `ModelSpecStore` (`service.modelSpecs`).

- **1.x downloaded models.drawthings.ai on every connection. 2.0 makes no network request
  by default**: specs come from the server's echo and a bundled snapshot refreshed each release.
  Opt in with `ConnectionOptions(modelSpecs: .bundledAndRemote())`.
- Register specs for custom models with `await service.modelSpecs.register([...])`.
- The override now also includes the refiner's and stage models' specs.

## Configuration

| 1.x | 2.0 |
|---|---|
| `seed: Int64?` (truncated to 32 bits) | `seed: UInt32?`, `nil` = random |
| `seedMode: Int32` | `seedMode: SeedMode` (`.legacy`, `.torchcpucompatible`, `.scalealike`, `.nvidiagpucompatible`) |
| `width`/`height`/hires-fix sizes rounded to 64 by `didSet` (not in the initializer) | stored as given; rounded to 64 when encoded |
| `toFlatBufferData()` could trap on negative or oversized values | throws `DrawThingsError.invalidConfiguration(field:reason:)`; see `validate()` |
| `ControlConfig` properties `let` | `var`, plus `noPrompt`, `downSamplingRate`, `inputOverride`, `targetBlocks` |
| `LoRAConfig` properties `let` | `var` |
| | new: `shiftForAudio`, `usesSolAttention`, `solAttentionStart`, `solAttentionTau` |
| | `Codable` (Draw Things JSON), `Hashable` |

### JSON (from DrawThingsKit)

DrawThingsKit's `ConfigurationCodable.swift` moved into the client and was rewritten to Draw Things'
own format. The API names are the same, so Kit users only drop the Kit version:

| DrawThingsKit | DrawThingsClient 2.0 |
|---|---|
| `toJSON(includeSeed:)`, `fromJSON(_:)`, `mergeJSON(_:)`, `validateJSON(_:)`, `formatJSON(_:)` | same names on `DrawThingsConfiguration` |
| `ConfigurationJSON`, `ConfigurationJSON.LoRAJSON`, `ConfigurationJSON.ControlJSON` | removed; `DrawThingsConfiguration`, `LoRAConfig` and `ControlConfig` are `Codable` |
| `ConfigurationCodableError` | `DecodingError` / `DrawThingsError` |

Output is now complete Draw Things JSON that pastes into the app. It includes fields Kit dropped,
such as `compressionArtifacts`, `colorCalibration` and every control setting. Input accepts Kit's
older spellings. The app's compact "Copy Configuration" is an overlay: apply it with `mergeJSON`
on a base configuration.

`Examples/ConfigfromJSON.swift` is removed; use `DrawThingsConfiguration.fromJSON(_:)`.

## Images, tensors and hints

| 1.x | 2.0 |
|---|---|
| `LatentModelFamily` | `ModelFamily` (deprecated alias kept); adds `audioSampleRate` |
| `ImageHelpers` (struct) | `ImageHelpers` (namespace enum) |
| `dtTensorToImage` | still available; `dtTensorToCGImage` is the `Sendable` primitive |
| `nsImageToDTTensor`, `dtTensorToNSImage`, `dataToNSImage`, `createMaskFromImage` | removed |
| `resizeImage(_:to:)` size in points (2×/3× pixels on Retina/iPhone) | size in **pixels**; `resizedImage(_:width:height:)` for `CGImage` |
| `scaleImageToCanvas`, `fillTransparentAreas` rendered at screen scale | exact pixel size; `CGImage` forms `scaledImageToCanvas`, `filledTransparentAreas` |
| `cgImageRepresentation` ignored `UIImage` orientation | returns upright pixels |
| NaN/∞ decoded to mid-gray | NaN to mid-gray, ±∞ clamp to black/white |
| `AudioHelpers.ccvTensorToAudioBuffer(_:sampleRate:)` default 16 kHz | default 24 kHz; prefer `GeneratedAudio(tensor:sampleRate:)` |
| | `loadCGImage(from:)`, `decodeCGImage(_:)`, `pngData(for:)` apply EXIF orientation |

`HintBuilder` is now a `Sendable` struct:

```swift
// 1.x
let hints = HintBuilder().addPose(pose).addDepthMap(depth).build()

// 2.0
var builder = HintBuilder()
builder.addPose(pose)
builder.addDepthMap(depth)
let hints = try builder.build()   // throws HintBuildError instead of dropping unreadable images
```

`clear()` is now `removeAll()`. DrawThingsKit's `@_exported import class DrawThingsClient.HintBuilder`
must become `@_exported import struct`.

## Errors

`DrawThingsError` is new: `connectionFailed`, `unauthenticated`, `invalidConfiguration`,
`decodingFailed`, `incompleteResponse`, `server(code:message:)`. Cancellation is always
`CancellationError`.

## Media for video apps (DrawThingsVideoKit)

`GenerationResult` carries what VideoKit previously took from DrawThingsQueue:

| Previously | 2.0 |
|---|---|
| `result.images: [PlatformImage]` | `result.images: [CGImage]`, `result.platformImages` |
| `result.audioData: [Data]` (WAV) | `result.audio.map { $0.wavData() }` |
| `request.configuration.numFrames > 1` | `result.media.isVideo` (only true for video models; `numFrames` defaults to 14 for every configuration) |
| `LatentModelFamily.detect(from: model).nativeFrameRate ?? 16` | `result.media.frameRate` |
| Queue's `defaultAudioSampleRate(forModelFile:)` | `result.media.audioSampleRate`, `ModelFamily.audioSampleRate` |

## Removed

- `DrawThingsClient` class, `GenerationOutput`, `ImageGenerationProgress`
- `DrawThingsService.init(address:useTLS:)`, `generateImage(…)`, the per-call `sharedSecret` parameter
- `ModelSpecProvider`
- the ControlPanel service stubs
- deprecated `ImageHelpers` NSImage methods and `createMaskFromImage`
- `Examples/ConfigfromJSON.swift`
