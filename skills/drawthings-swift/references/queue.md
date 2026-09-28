# DrawThingsQueue reference

`GenerationQueue` (module `DrawThingsQueue`, `@MainActor @Observable`) runs requests one at a time,
in order, on a `DrawThingsService`.

```swift
import DrawThingsClient
import DrawThingsQueue

let queue = GenerationQueue(
    service: service,
    storage: QueueStorage()     // optional; or QueueStorage(fileURL:) for your own location
)
try await queue.restore()       // re-add jobs saved by an earlier run (no-op without storage)

let job = queue.enqueue(request, name: "Fox")          // returns a QueueJob
queue.enqueue(contentsOf: requests)

for await result in queue.results {                    // each completed GenerationResult
    for (index, image) in result.images.enumerated() {
        try ImageHelpers.saveImage(image, to: folder.appending(path: "\(result.id)-\(index).png"))
    }
}
```

## State (observable)

- `pending: [QueueJob]`, `current: QueueJob?`, `finished: [QueueJob]` (oldest first, up to
  `maxFinishedJobs`, default 50), `jobs` (all three), `isProcessing`.
- `progress: GenerationProgress?`, `preview: CGImage?`, `remoteDownload` for the running job.
- `isPaused`, `pauseReason: String?`.
- `job(_ id:) -> QueueJob?`.

`QueueJob` is a value: `id` (the request's), `request`, `name`, `createdAt`, `status`
(`.pending`, `.running`, `.completed`, `.failed`, `.cancelled`; `status.isFinished`), `startedAt`,
`completedAt`, `duration`, `result: GenerationResult?`, `error: (any Error)?`, `retryCount`. A copy
keeps the state it had when read; look it up again with `job(_:)`.

## Control

| Call | Effect |
|---|---|
| `pause()`, `pause(reason:)`, `resume()` | Pausing stops new jobs; the running job finishes |
| `cancel(_ id:) -> Bool`, `cancelAll()` | Pending or running; cancelled jobs move to `finished` |
| `retry(_ id:) -> Bool`, `canRetry(_:)`, `maxRetries` (3) | Failed job back to the end of the queue |
| `movePending(fromOffsets:toOffset:)` | Same arguments as SwiftUI `onMove` |
| `remove(_ id:)` | Pending or finished job |
| `clearCompleted()`, `clearFailed()`, `clearFinished()`, `clearAll()` | Housekeeping |
| `service` (settable) | Switch server; affects jobs started afterwards |

## Streams

`events: AsyncStream<QueueEvent>` (`.added`, `.started`, `.progress(id, progress)`, `.completed`,
`.failed`, `.cancelled`, `.removed(id)`, `.paused(reason:)`, `.resumed`) and
`results: AsyncStream<GenerationResult>`. **Each access creates a new subscription that sees events
from then on**, so subscribe (read the property) before enqueueing if you need every result.

## Behavior worth knowing

- A request whose configuration has no seed gets a random `UInt32` seed when queued.
- Lost connection (`DrawThingsError.connectionFailed`): the job goes back to the front, the queue
  pauses with a `pauseReason` beginning "Connection lost". Fix the connection (or set `service`) and
  call `resume()`. Other errors mark the job `.failed`.
- `QueueStorage` saves pending and running jobs whole (configuration as Draw Things JSON, image and
  mask as PNG, hints and overrides as protobuf) after every change, off the main actor. Its default
  file is `Application Support/DrawThingsQueue/queue.json`; it also reads files written by the old
  DrawThingsQueue 0.x (those lack images and hints).
- One `GenerationQueue` per server connection is the normal pattern; feed its `results` to a
  `VideoProcessor` for video (see `video.md`).
