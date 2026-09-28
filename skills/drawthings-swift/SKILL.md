---
name: drawthings-swift
description: Build macOS and iOS Swift apps that generate images, video and audio with a Draw Things gRPC server using the DrawThings-Swift package (DrawThingsClient, DrawThingsQueue, DrawThingsVideoKit, DrawThingsKit). Use this skill whenever code imports any of those modules, whenever someone wants to call Draw Things (the Draw Things app's API server, gRPCServerCLI, or Draw Things+ through a bridge) from Swift, generate or queue images or videos from SwiftUI, turn generated frames into an MP4, read or write Draw Things configuration JSON, or upgrade from DrawThingsClient 1.x or the separate DrawThingsQueue, DrawThingsVideoKit or DrawThingsKit packages, even if the package isn't named.
---

# DrawThings-Swift

DrawThings-Swift talks to a [Draw Things](https://drawthings.ai) gRPC server from Swift 6 apps on
macOS 15+ and iOS 18+. Version 2 is a rewrite: much of what models know about "DrawThingsClient"
describes 1.x and no longer compiles. Use the APIs in this skill, and when unsure, read the
package source (in `.build/checkouts/DrawThings-Swift/` or Xcode's package cache) rather than guess.

## Pick the products

```swift
// Package.swift
.package(url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift", from: "2.2.0"),

// target dependencies: add only what the app uses
.product(name: "DrawThingsClient", package: "DrawThings-Swift"),    // always
.product(name: "DrawThingsQueue", package: "DrawThings-Swift"),     // many jobs in order
.product(name: "DrawThingsVideoKit", package: "DrawThings-Swift"),  // frames -> MP4
.product(name: "DrawThingsKit", package: "DrawThings-Swift"),       // saved servers, model catalog, config state
```

| Need | Use |
|---|---|
| One generation at a time in SwiftUI | `DrawThingsSession` (DrawThingsClient) |
| Scripts, CLIs, services, full control | `DrawThingsService` (DrawThingsClient) |
| Batches, a job list, pause/retry, jobs that survive relaunch | `GenerationQueue` (DrawThingsQueue) |
| A video file from a video model's frames and audio | `VideoProcessor` / `VideoAssembler` (DrawThingsVideoKit) |
| Server profiles, a model picker, the "current settings" of an app | `ConnectionManager`, `ModelsManager`, `ConfigurationManager` (DrawThingsKit) |

`import DrawThingsKit` also imports DrawThingsClient. The library ships **no SwiftUI views**; its
state types are `@Observable`, so build views on them (see `references/swiftui.md`).

## Rules that prevent the common failures

1. **Model settings must suit the model.** Sampler, guidance and shift differ per model, and the
   `DrawThingsConfiguration()` defaults are Draw Things' preset for Z Image Turbo, so they are wrong
   for any other model: changing only `model` is not enough. With unsuitable settings the server renders nothing, the client throws
   `DrawThingsError.incompleteResponse`, and some servers crash on the next request. Best source of
   correct settings: Draw Things itself. The user sets up the model in the app, uses Copy
   Configuration, and the app loads that JSON (`DrawThingsConfiguration.fromJSON(_:)`, or
   `mergeJSON(_:)` onto a base). Known-good example, Z Image Turbo:
   `DrawThingsConfiguration(width: 1024, height: 1024, steps: 8, model: "z_image_turbo_1.0_q8p.ckpt", sampler: .unipctrailing, guidanceScale: 1, shift: 3, resolutionDependentShift: false)`.
   Don't invent settings for other models; ask for the copied configuration or leave a clear TODO.
2. **Security must match the server.** The Draw Things app's API server uses TLS by default:
   `ConnectionOptions(security: .tls())` (the default). Use `.plaintext` only when the server has
   TLS off. A mismatch fails as `DrawThingsError.connectionFailed`. Local-network servers' self-signed
   certificates are accepted automatically; public hosts are verified.
3. **Shared secret** goes in `ConnectionOptions(sharedSecret:)` once, not per call. A missing or
   wrong one throws `DrawThingsError.unauthenticated`.
4. **Images are `CGImage`.** Pass input and mask as `CGImage` in `GenerationRequest`; convert
   `NSImage`/`UIImage` with `.cgImageRepresentation` (applies orientation). A mask's *transparent*
   pixels are regenerated. Never encode a mask yourself with `ImageHelpers.imageToDTTensor`; the
   client builds Draw Things' mask format. Sizes are pixels and are rounded down to multiples of 64.
5. **Cancel by cancelling the task.** Cancelling the Swift task that consumes `service.stream(_:)`
   or awaits `generate(_:)` (or breaking out of the loop) cancels on the server. There is no
   cancel token.
6. **Call `await service.shutdown()`** when an app-owned service is no longer needed (not needed
   for `DrawThingsSession` or DrawThingsKit's `ConnectionManager`, which manage theirs).
7. **Seeds are `UInt32?`**; `nil` means random. `GenerationQueue` assigns a random seed when it
   queues a request without one, so results are reproducible.
8. **Video**: decide "is this a video" and "what frame rate" with `result.media.isVideo` and
   `result.media.frameRate`, not `numFrames > 1` (every configuration defaults to 14 frames) or a
   hard-coded 16/24.
9. **Swift 6 isolation**: `DrawThingsService` is an actor (its `stream(_:)` is `nonisolated`);
   `DrawThingsSession`, `GenerationQueue`, `VideoProcessor`, `ConnectionManager`, `ModelsManager`
   and `ConfigurationManager` are `@MainActor`. Requests, results, events and configurations are
   `Sendable` values.

## Quick start: one image

```swift
import DrawThingsClient

let service = try DrawThingsService(address: "localhost:7859")   // host:port; IPv6 as [::1]:7859
let request = GenerationRequest(
    prompt: "A lighthouse on a rocky coast at sunset",
    configuration: DrawThingsConfiguration(
        width: 1024, height: 1024, steps: 8, model: "z_image_turbo_1.0_q8p.ckpt",
        sampler: .unipctrailing, guidanceScale: 1, shift: 3, resolutionDependentShift: false
    )
)

for try await event in service.stream(request) {
    switch event {
    case .progress(let progress): print(progress.stage, progress.fractionCompleted ?? 0)
    case .preview(let preview): show(preview)                     // CGImage
    case .remoteDownload(let download): print(download.fractionCompleted ?? 0)
    case .image(let image, let index): save(image, index)         // each final image
    case .audio(let audio): _ = audio.wavData()                   // GeneratedAudio
    case .completed(let result): print(result.duration)           // always last
    }
}
// or simply: let result = try await service.generate(request); result.images / result.platformImages

try ImageHelpers.saveImage(image, to: url, format: .png)
await service.shutdown()
```

## Quick start: SwiftUI

```swift
import DrawThingsClient
import SwiftUI

struct ContentView: View {
    @State private var session = try! DrawThingsSession(address: "localhost:7859")
    @State private var image: CGImage?

    var body: some View {
        VStack {
            if let progress = session.progress {
                ProgressView(value: progress.fractionCompleted ?? 0) { Text(progress.stage.description) }
            }
            if let shown = session.preview ?? image {
                Image(decorative: shown, scale: 1).resizable().scaledToFit()
            }
            Button("Generate") {
                Task {
                    // A failure is also kept in session.lastError.
                    let result = try? await session.generate(prompt: "A red fox in snow", configuration: zImageTurbo)
                    image = result?.images.first ?? image
                }
            }
            .disabled(!session.isConnected || session.isGenerating)
        }
        .task { await session.connect() }
    }
}
```

`DrawThingsSession` runs one generation at a time (`SessionError.busy` otherwise) and exposes
`isConnected`, `serverInfo`, `isGenerating`, `progress`, `preview`, `remoteDownload`, `lastResult`,
`lastError` and `cancel()`. For more than one job, use `GenerationQueue`.

## Where to read more

Read only the file the task needs:

| Task | Read |
|---|---|
| Connection options, TLS, img2img, inpainting, LoRAs, ControlNet and hints, Draw Things JSON, model specs for custom models, image helpers, errors | `references/client.md` |
| Queues, batch jobs, saved queues, lost connections | `references/queue.md` |
| Video models, audio, MP4 assembly, interpolation, super resolution | `references/video.md` |
| Server profiles, model catalog and pickers, configuration state (DrawThingsKit) | `references/kit.md` |
| SwiftUI views on the observable types, macOS app activation from a Swift package | `references/swiftui.md` |
| Code written for 1.x or for the separate Queue/VideoKit/Kit packages | `references/migrating.md` |

The package's `README.md`, `MIGRATING-2.0.md` and `Examples/DrawThingsExample` (a complete SwiftUI
app using all four products) are the authoritative long-form docs.

## Before you finish

- Build it (`swift build` or `xcodebuild`); these APIs are strict Swift 6.
- Make sure every configuration either came from Draw Things JSON or uses settings known to suit its
  model. If you had to guess, say so to the user.
- Don't claim a generation works without a server to test against. Say how to try it: the Draw
  Things app with its API server turned on (port 7859 by default, TLS on), or `gRPCServerCLI`.
