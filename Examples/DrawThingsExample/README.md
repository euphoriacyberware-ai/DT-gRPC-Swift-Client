# DrawThingsExample

A small SwiftUI app for macOS and iOS built on the DrawThings-Swift products. The library ships no
views; this app shows how to build them on its observable types, using only the public API.

| Tab | Shows | Built on |
|---|---|---|
| Generate | Prompt, model, size, "Paste Configuration from Draw Things", the running job's preview | `ConfigurationManager`, `ModelsManager`, `GenerationQueue` |
| Queue | Running job with progress and preview; pending jobs (drag to reorder, swipe to cancel); finished jobs (retry, remove); pause, resume, cancel all | `GenerationQueue`, `QueueJob` |
| Video | Codec, quality, interpolation and super resolution settings; assembly progress; the latest video; collected frames | `VideoProcessor` fed by `queue.results` |
| Servers | Saved servers, connection status, profile editor with shared secret | `ConnectionManager`, `ServerProfile` |

`AppModel` in `DrawThingsExampleApp.swift` wires them together: it connects to the default server,
creates the queue on the first connection (saved to Application Support, restored at launch),
and connects the video processor to the queue's results so video jobs become MP4 files (in
Movies/DrawThingsExample on macOS).

## Running

Open `Package.swift` in Xcode, choose the DrawThingsExample scheme and a Mac or iOS destination,
and run. On macOS, `swift run` in this folder also works.

The app starts with a Z Image Turbo configuration (`z_image_turbo_1.0_q8p.ckpt`, DPM++ 2M
Trailing, guidance 1, shift 3). Sampler, guidance and shift depend on the model, and a model given
unsuitable settings can fail on the server. For other models, set them up in Draw Things, use
Copy Configuration, and paste here.

The Servers tab starts with a `localhost:7859` profile using TLS, which matches the Draw Things
app's API server defaults.
