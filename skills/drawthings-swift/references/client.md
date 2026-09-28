# DrawThingsClient reference

## Contents
- Connecting and TLS
- Requests: text to image, image to image, inpainting
- LoRAs, ControlNet and hints
- Draw Things configuration JSON
- Model specifications for custom models
- Images and tensors, model families
- Errors and logging

## Connecting and TLS

```swift
let endpoint = try ServerEndpoint("192.168.1.20:7859")   // host:port, bare host (7859), [IPv6]:port
let service = DrawThingsService(endpoint: endpoint, options: ConnectionOptions(
    security: .tls(),                 // or .plaintext; must match the server
    sharedSecret: "my-secret",        // when the server requires one
    clientIdentity: ClientIdentity(user: "My App", device: .laptop),
    requestTimeout: .seconds(30),     // unary calls only; generations aren't limited
    modelSpecs: .bundled              // or .bundledAndRemote() for the live Draw Things model list
))
let reply = try await service.echo()  // checks the connection; reply.files lists installed models
```

`DrawThingsService(address:options:)` is the string shorthand (throws `ServerEndpointError` for a
bad address). Nothing connects until the first call. Call `await service.shutdown()` when done.

TLS verification (`.tls(verification:)`):

| Value | Behavior |
|---|---|
| `.automatic` (default) | Accepts self-signed certificates on local-network hosts (loopback, private and link-local addresses, `.local` and single-label names, names resolving only to such addresses); verifies public hosts |
| `.full` | Always verifies against the system trust store |
| `.trustRoots([pemData])` | Verifies a self-signed server reached over the internet |
| `.none` | Never verifies (encrypted, but open to interception) |

Server settings the client copes with: response compression on or off, TLS on or off (match it),
Bridge Mode to Draw Things+ (some models run only locally), model browsing on or off (off means the
server reports no models; the client falls back to its bundled specs), shared secret.

## Requests

```swift
var configuration = DrawThingsConfiguration(
    width: 1024, height: 1024, steps: 8,
    model: "z_image_turbo_1.0_q8p.ckpt",
    sampler: .unipctrailing, guidanceScale: 1,
    seed: 12345,                      // UInt32?, nil = random
    shift: 3, resolutionDependentShift: false
)
let request = GenerationRequest(
    prompt: "A watercolor of a harbor",
    negativePrompt: "blurry",
    configuration: configuration,
    image: inputImage,    // CGImage: image-to-image canvas
    mask: maskImage,      // CGImage: transparent pixels are regenerated
    hints: try hints.build(),
    modelFamily: nil,     // override for model files the name doesn't identify
    audioSampleRate: nil  // override for custom audio models
)
```

- `configuration.validate()` throws `DrawThingsError.invalidConfiguration(field:reason:)` for values
  the server can't take; generation calls it for you, so bad values throw instead of crashing.
- Image to image: set `strength` (for example 0.6) and pass `image`. Inpainting: `strength = 1`,
  pass `image` and `mask`; set `enableInpainting` for models that need the inpaint control.
- `batchCount`/`batchSize` above 1 return several images, in order, in `result.images`.

## LoRAs, ControlNet and hints

```swift
// LoRAs and ControlNets must be made for the configuration's model family. Draw Things ships
// none for Z Image Turbo; these names stand for files the user imported.
configuration.loras = [
    LoRAConfig(file: "my_z_image_style_lora_f16.ckpt", weight: 0.8),   // mode: .all (or .base, .refiner)
]
configuration.controls = [
    ControlConfig(file: "my_depth_controlnet_f16.ckpt", weight: 0.8, guidanceEnd: 0.7, controlMode: .control),
]

var hints = HintBuilder()                   // a value type; methods are mutating
hints.addMoodboardImage(referencePNG)        // Data: PNG/JPEG/HEIC, EXIF orientation applied
hints.addDepthMap(depthPNG, weight: 0.8)
hints.addHint(type: .tile, imageData: tileJPEG)
let request = GenerationRequest(prompt: "...", configuration: configuration, hints: try hints.build())
```

Other hint methods: `addPose`, `addCannyEdges`, `addScribble`, `addColorReference`, `addLineArt`,
`addMoodboardImages`. `build()` throws `HintBuildError` for data it can't decode. A LoRA with no
known spec is sent with a minimal one based on the model's version, because the server silently
skips LoRAs it has no spec for.

## Draw Things configuration JSON

`DrawThingsConfiguration` is `Codable` in the app's own JSON format.

```swift
let configuration = try DrawThingsConfiguration.fromJSON(json)     // missing keys take defaults
var merged = base
try merged.mergeJSON(copiedJSON)                                    // only keys in the JSON change
let json = try configuration.toJSON()                               // complete, pastes into the app
let check = DrawThingsConfiguration.validateJSON(text)              // .isValid, .error, .configuration
```

The app's **Copy Configuration** output is a compact overlay (only settings relevant to the current
model); apply it with `mergeJSON` onto a base, or `fromJSON` for defaults elsewhere. Complete exports
contain every key. JSON conventions: sizes in pixels; `seed` -1 = random; `sampler` and `seedMode`
integers; LoRA `mode` "all"/"base"/"refiner"; control `controlImportance` "balanced"/"prompt"/
"control"; `upscaler`, `faceRestoration`, `refinerModel` "" or null = none.

## Model specifications for custom models

The server needs each model's spec (version, latent space...) to run models it doesn't have built
in; without one it uses SD 1.x defaults and produces noise. The client resolves specs in this order:
specs the app registered, the live list (only with `.bundledAndRemote()`), the snapshot bundled with
the package, then the specs the server reports (none when model browsing is off).

```swift
if let spec = ModelSpec(json: specJSON) {            // Draw Things model-spec JSON with a "file" key
    await service.modelSpecs.register([spec])
}
```

Built-in models (including `_q8p` quantized variants) are known to every server. Passing
`GenerationRequest.override` sends your own `MetadataOverride` instead.

## Images and tensors

The service converts images for you. For custom use:

```swift
let tensor = try ImageHelpers.imageToDTTensor(cgImage, forceRGB: true)
let image = try ImageHelpers.dtTensorToCGImage(tensor, modelFamily: .flux)
let upright = try ImageHelpers.loadCGImage(from: url)                 // applies EXIF orientation
try ImageHelpers.saveImage(image, to: outputURL, format: .png)        // or .jpeg, jpegQuality:
let png = try ImageHelpers.pngData(for: image)
let resized = ImageHelpers.resizedImage(image, width: 1024, height: 768)   // exact pixels
```

Every helper has a `CGImage` form and a `PlatformImage` (`NSImage`/`UIImage`) form; results are
rendered at one pixel per point. `result.platformImages` gives the results as platform images.

Model families (`ModelFamily.detect(from:)`) decide how previews are decoded, the frame rate and
the audio sample rate: `.sd1` (SD 1.x/2.x, SVD), `.sdxl`, `.sd3`, `.flux`, `.flux2`, `.qwen`,
`.qwen21`, `.zImage`, `.wan21` (16 fps), `.wan22` (24 fps), `.hunyuanVideo` (30 fps), `.ltx2`
(25 fps, 24 kHz audio), `.ltx23` (25 fps, 48 kHz), `.minimaxH3` (24 fps, 32 kHz), `.longcatVideoAvatar`
(25 fps, 16 kHz), `.hiDreamO1`, `.kandinsky`, `.wurstchen`. A model's spec can set its own frame
rate; `result.media.frameRate` accounts for it.

## Errors and logging

```swift
do {
    let result = try await service.generate(request)
} catch is CancellationError {
    // cancelled by the app
} catch let error as DrawThingsError {
    switch error {
    case .connectionFailed(let detail): ...          // unreachable, TLS mismatch, rejected certificate
    case .unauthenticated: ...                       // shared secret missing or wrong
    case .invalidConfiguration(let field, let reason): ...
    case .decodingFailed(let detail): ...
    case .incompleteResponse(let detail): ...        // stream ended early, or no image (often unsuitable settings)
    case .server(let code, let message): ...         // gRPC error from the server
    }
}
```

`DTLogger` (os.log, subsystem `com.drawthings`) is off by default:
`DTLogger.minimumLevel = .debug` and `DTLogger.shared.logToConsole = true`. Categories include
`.connection`, `.queue`, `.generation`, `.grpc`, `.models`, `.video`.
