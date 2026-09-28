# DrawThingsVideoKit reference

## Video generation

Video models (Wan, HunyuanVideo, LTX-2, MiniMax H3, LongCat...) return their frames as
`result.images`, in order, and some return audio in `result.audio`.

```swift
let result = try await service.generate(request)   // configuration from Draw Things JSON for the video model
result.media.isVideo        // true for a video model generating more than one frame
result.media.frameRate      // Int?, from the model's spec or family (e.g. 24 for MiniMax H3)
result.media.audioSampleRate
if let audio = result.audio.first {                // GeneratedAudio: planar Float channels
    try audio.wavData().write(to: wavURL)          // 32-bit float WAV
    let buffer = try audio.pcmBuffer()             // AVAudioPCMBuffer
}
```

Video models are especially sensitive to settings (frame count, steps, sampler, guidance, shift,
refiner); load them from the configuration the user copies from Draw Things. `numFrames` is the
frame count sent to the server.

## VideoProcessor: results to MP4 automatically

```swift
import DrawThingsVideoKit

let processor = VideoProcessor(configuration: VideoProcessorConfiguration(   // @MainActor @Observable
    autoAssemble: true,
    minimumFrames: 2,
    defaultVideoConfiguration: VideoConfiguration(outputURL: defaultURL),
    clearFramesAfterAssembly: true,
    configurationProvider: { jobID in                     // @Sendable; optional, e.g. a file per job
        VideoConfiguration(outputURL: folder.appending(path: "\(jobID).mp4"))
    }
))
processor.connect(to: queue.results)      // any AsyncSequence of GenerationResult that is Sendable
processor.ingest(result)                  // or feed results yourself

for await event in processor.events {     // new subscription per access
    switch event {
    case .assemblyCompleted(let jobID, let url): print(jobID, url)
    case .assemblyFailed(_, let error): print(error)
    default: break
    }
}
```

It collects only video results (`result.media.isVideo`; set `collectAllCompletedJobs` for all),
encodes at `result.media.frameRate`, and muxes the first audio track unless the configuration names
its own audio. Automatic assemblies run one at a time, in arrival order. Observable state:
`collectedFrames`, `isAssembling`, `assemblyProgress`, `lastOutputURL`, `lastError`. Also
`assembleCollectedFrames(configuration:)`, `assemble(frames:configuration:)`,
`assemble(urls:configuration:)`, `addFrames`, `removeFrames(at:)`, `clearFrames()`, `disconnect()`.

## VideoAssembler: encode frames yourself

```swift
let url = try await VideoAssembler().assemble(       // actor
    frames: VideoFrameCollection(cgImages: result.images),
    configuration: VideoConfiguration(
        outputURL: outputURL,
        sourceFrameRate: result.media.frameRate ?? 16,
        codec: .h264,                                // .hevc, .proRes422, .proRes4444
        quality: .high,
        audioData: result.audio.first?.wavData()
    ),
    progress: { fraction in print(fraction) }        // @Sendable, any thread
)
```

- Without interpolation the video plays at `sourceFrameRate`. With
  `interpolation: .enabled(factor: 2)` it plays at `frameRate`; set `frameRate = sourceFrameRate * factor`
  to keep the duration. `interpolationPassMode: .multiPass` runs 2×2× for factor 4.
- Interpolation uses VTFrameProcessor (macOS 15.4+, iOS 26+, not the simulator) or a Core Image
  cross-dissolve; `FrameInterpolator.isVTFrameProcessorAvailable` tells you which.
- `superResolution: .enabled(factor: 2)` upscales before interpolation with VTSuperResolutionScaler
  (macOS/iOS 26+, input up to 1920×1080; `SuperResolutionScaler.modelStatus(...)` and
  `downloadModels(...)` manage Apple's model) or Lanczos scaling.
- All frames must be the same size; errors are `VideoAssemblerError`.
- `VideoFrameCollection.save(to:)` / `load(from:)` keep frames, audio and metadata in a folder for
  re-encoding later.
- Sandboxed macOS apps writing to a user-chosen folder need the
  `com.apple.security.files.user-selected.read-write` entitlement.
