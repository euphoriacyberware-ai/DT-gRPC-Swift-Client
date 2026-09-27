# Changelog

All notable changes to DrawThingsClient are documented here. The project follows
[Semantic Versioning](https://semver.org).

## 2.0.0 — Unreleased

A major rework for Swift 6. See [MIGRATING-2.0.md](MIGRATING-2.0.md) for the API mapping.

### Requirements
- macOS 15 / iOS 18, Swift 6 language mode, grpc-swift 2.

### Added
- `DrawThingsService.stream(_:)`: an `AsyncThrowingStream` of `GenerationEvent`s (progress, preview,
  remote download, image, audio, completed) in server order, and `generate(_:)` returning a
  `GenerationResult`. Cancelling cancels the generation on the server.
- `GenerationRequest`, `GenerationProgress` and `GenerationResult` value types.
- `DrawThingsClientUI` product with an `@Observable` `DrawThingsSession`.
- `ConnectionOptions`: TLS verification policy, shared secret, client identity, message size,
  request timeout and model spec source. `ServerEndpoint` parses IPv6 addresses.
- `MediaProfile` and `GeneratedAudio` (planar PCM, `AVAudioPCMBuffer` and in-memory WAV).
  `ModelFamily.audioSampleRate`.
- Draw Things JSON: `DrawThingsConfiguration`, `LoRAConfig` and `ControlConfig` are `Codable` in the
  app's format, with `toJSON`, `fromJSON`, `mergeJSON`, `validateJSON` and `formatJSON` (moved
  from DrawThingsKit and rewritten to match the app).
- `DrawThingsConfiguration.validate()`; configuration fields `shiftForAudio`, `usesSolAttention`,
  `solAttentionStart`, `solAttentionTau`; full `ControlConfig` settings.
- `ModelSpecStore` with app-registered specs; the override includes refiner and stage models.
- `DrawThingsError`.
- `CGImage` forms of all image helpers; `loadCGImage(from:)` and `decodeCGImage(_:)` apply EXIF
  orientation.
- `Scripts/generate.sh` (code generation from a local draw-things-community checkout) and
  `Scripts/update-model-specs.sh`.
- CI for macOS and iOS; a weekly workflow that refreshes the bundled model specs.
- An in-process gRPC test server; 108 tests on Swift Testing.

### Changed
- No network request by default: the models.drawthings.ai fetch is opt-in
  (`.bundledAndRemote()`), and the bundled snapshot is refreshed before releases (now 246 specs).
- TLS verifies public servers; local-network servers (including names that resolve to LAN
  addresses) keep accepting Draw Things' self-signed certificate.
- The service connects on first use and has an async `shutdown()`.
- `seed` is `UInt32?`; `seedMode` is `SeedMode`.
- `LatentModelFamily` is renamed `ModelFamily` (deprecated alias).
- `HintBuilder` is a `Sendable` struct whose `build()` throws.
- `ImageHelpers` and `AudioHelpers` are namespace enums.
- Image encoding and decoding use Accelerate (2048×2048 encode 25 → 9 ms, decode 15 → 2 ms).

### Fixed
- Audio could be missing from results, and progress and previews could arrive out of order.
- SwiftUI progress never updated (`ImageGenerationProgress` was a nested `ObservableObject`).
- Progress wasn't cleared after an error.
- Concurrent callers could skip the remote model spec fetch, and a failed fetch was never retried.
- Invalid configuration values trapped instead of throwing.
- Resized images were 2×/3× the requested size on Retina Macs and iPhones; `UIImage` orientation
  was ignored.
- `CGContext` wrote through a dangling pointer; tensor headers were read with misaligned loads;
  malformed or truncated tensors (including fpzip streams) could read out of bounds.
- `deinit` blocked and could trap on an event-loop thread.
- IPv6 addresses didn't parse; TLS to an IPv4 address failed (the IP was sent as the TLS server name).
- 4 MiB image chunks plus framing exceeded gRPC's default message limit.
- MiniMax H3 / LTX-2 decoded frames were cropped by the audio-row stripping meant for latents.
- Model specs were missing for 47 newer models (MiniMax H3, Qwen Image 2.1, Krea 2 Turbo, Ideogram 4…).

### Removed
- The `DrawThingsClient` class, `GenerationOutput`, `ImageGenerationProgress`, the closure-based
  `generateImage`, `ModelSpecProvider`, the ControlPanel stubs, deprecated `ImageHelpers` NSImage
  methods and `createMaskFromImage`, and `Examples/ConfigfromJSON.swift`.

## 1.7.2

- Removed the unsafe compiler flags from `CFpzip` so the package can be required by version.
  Every release from 1.6.0 to 1.7.1 failed as a version-pinned dependency.
- Added fpzip and deflate round-trip tests.
