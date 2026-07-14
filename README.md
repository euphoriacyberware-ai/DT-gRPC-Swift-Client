<p align="center">
  <img src="Assets/logo.png" alt="DrawThingsClient Logo" width="200"/>
</p>

# DrawThingsClient

A Swift client library for interacting with Draw Things gRPC server, designed for easy integration with SwiftUI applications on macOS and iOS.

## Features

- **Modern Swift Concurrency**: Built with async/await for clean, readable asynchronous code
- **SwiftUI Integration**: ObservableObject-based client with @Published properties for reactive UI updates
- **Progress Tracking**: Real-time progress updates during image generation
- **Image Utilities**: Built-in helpers for image conversion and manipulation
- **Type Safety**: Full Swift type safety with generated protobuf code
- **Legacy Processor Support**: Library runs on both Intel and Apple Silicon processors

## Feature Status

### ✅ Tested & Working

The following features have been tested and confirmed working:

- **Text-to-Image Generation**: Basic image generation from text prompts
- **Image-to-Image**: Transform existing images based on prompts
- **Inpainting**: Selective image editing with masks
- **Moodboard/Reference Images**: Using reference images to influence generation (shuffle hints)
- **ControlNet Support**: Using ControlNet models for guided generation (e.g., PuLID, depth, pose, etc.)
- **LoRA Support**: Apply LoRA models to modify generation style
- **Video Generation**: Generate video/animation sequences (frames returned sequentially)
- **Image-to-Video**: Generate video from a starting image
- **Progress Tracking**: Real-time generation progress updates
- **Preview Images**: Receive preview images during generation
- **Model Metadata**: Query available models and samplers
- **Multi-stage Models**: Stage 2 parameters for multi-stage generation pipelines
- **Advanced Optimization**: TEA Cache and other performance optimizations
- **Shared Secret**: API support for using a shared secret with your gRPC server connection
- **Response Compression**: The library can receive compressed responses from the gRPC server
- **Audio**: Audio functionality (for LTX-2) is implemented

### ⚠️ Untested Features

The following features are available in the protocol but have not yet been tested:
- **File Upload**: Uploading models or other files to the server

## Requirements

- macOS 14.0+
- iOS 17.0+ (if building for iOS)
- Xcode 15.0+
- Swift 5.9+
- Draw Things app with gRPC server enabled or standalone gRPC server for nVidia

### Draw Things Server Setup

To use this framework, you need to configure the Draw Things gRPC server with the following settings:

1. **Response Compression**: May be **enabled** or **disabled**
   - Having server-side compression enabled is supported, the client has the ability to decompress the responses
   
2. **Transport Layer Security**: May be **enabled** or **disabled**
   - Either mode is supported, enabling TLS is recommended
   
3. **Bridge Mode**: May be **enabled** or **disabled**
   - Generation pass through to another server, including DT+ is supported
   - Bring Your Own LoRA (BYOL) feature of DT+ is not supported in Bridge Mode currently. This is a DT+ service limitation, not a limitation of the DrawThingsClient

2. **Enable Model Browsing**: Recommended to be **enabled**
   - This allows the framework to query available checkpoint models, controlnets, LoRAs, etc.
   - Required for proper initialization and model selection in a UI
   
3. **Share Secret**: May be **enabled** or **disabled**
    - The shared secret is implemented in the client but the application must also support passing that optional paramter with the generation request.

## Important: Image Data Formats

Draw Things uses a custom tensor format (DTTensor) for image data exchange, **not** standard image formats like PNG or JPEG. Understanding this is critical for successful integration.

### DTTensor Format

The DTTensor format consists of:
- **68-byte header** containing dimensions, channel count, and compression identifier
- **Float16 RGB pixel data** with values in range [-1, 1] (raw or compressed with deflate/fpzip)

The `ImageHelpers` class provides conversion utilities:

```swift
// Convert PlatformImage to DTTensor (for sending to Draw Things)
let tensorData = try ImageHelpers.imageToDTTensor(image, forceRGB: true)

// Convert DTTensor to PlatformImage (for receiving from Draw Things)
let image = try ImageHelpers.dtTensorToImage(tensorData)

// For preview images (16-channel latents), specify the model family for correct colors
let family = LatentModelFamily.detect(from: "flux1-dev.gguf")
let previewImage = try ImageHelpers.dtTensorToImage(previewData, modelFamily: family)
```

**Note:** `PlatformImage` is a type alias that resolves to `NSImage` on macOS and `UIImage` on iOS.

### Model Family Detection for Previews

Preview images from Draw Things are 16-channel latent representations that need model-specific coefficients for correct color conversion. The `LatentModelFamily` enum handles this:

```swift
// Detect from model filename or version string
let family = LatentModelFamily.detect(from: "flux1_dev_q8p.ckpt")     // .flux
let family = LatentModelFamily.detect(from: "qwenImage")              // .qwen (version string)
let family = LatentModelFamily.detect(from: "wan21_1_3b")             // .wan21 (version string)

// Convert preview with correct colors
let previewImage = try ImageHelpers.dtTensorToImage(previewData, modelFamily: family)
```

**Supported Model Families:**
| Family | Models | Latent Channels | Native FPS |
|--------|--------|-----------------|------------|
| `.sd1` | SD 1.x, SD 2.x, SVD | 4 | — |
| `.sdxl` | SDXL Base, SDXL Refiner, SSD-1B, PixArt, AuraFlow | 4 | — |
| `.sd3` | Stable Diffusion 3, SD3 Large | 16 | — |
| `.flux` | Flux.1, HiDream-I1, SeedVR2 | 16 | — |
| `.flux2` | Flux 2 (9B, 4B), Ernie Image, Ideogram 4 | 32 | — |
| `.qwen` | Qwen Image, Qwen Image Edit, Cosmos 2.5, Krea 2 | 16 | — |
| `.zImage` | Z Image | 16 | — |
| `.wan21` | Wan 2.1 (1.3B, 14B) | 16 | 16 |
| `.wan22` | Wan 2.2 5B | 48 | 16 |
| `.hunyuanVideo` | HunyuanVideo | 16 | 24 |
| `.ltx2` | LTX-2 | 16 | 25 |
| `.ltx23` | LTX-2.3 | 16 | 25 |
| `.hiDreamO1` | HiDream-O1 | 3072 (patch-packed) | — |
| `.kandinsky` | Kandinsky 2.1 | 4 (OKLab) | — |
| `.wurstchen` | Würstchen / Stable Cascade | 4 | — |

**Note:** `.sd1` (SD 1.x/2.x/SVD) and `.sdxl` use different 4-channel preview coefficients, so passing the correct family matters for accurate SD 1.x/2.x preview colors. `.hiDreamO1` decodes a patch-packed latent into a preview 32× larger per side. Cosmos 2.5, Krea 2, Ernie Image, Ideogram 4, and SeedVR2 reuse existing family coefficients (Qwen, Flux 2, and Flux respectively).

The `nativeFrameRate` property returns the model's native FPS for video models, or `nil` for image-only models:

```swift
let family = LatentModelFamily.detect(from: "wan21_1_3b")
if let fps = family.nativeFrameRate {
    print("Video model, native FPS: \(fps)")  // 16
}
```

**Note:** If using **DrawThingsKit**, you don't need to handle this manually - the Kit automatically detects model families and converts previews/results to native `PlatformImage` types.

### When to Use Each Format

| Data Type | Format Required | Conversion Method |
|-----------|-----------------|-------------------|
| **Hints/Moodboard images** | DTTensor | `imageToDTTensor()` |
| **ControlNet input images** | DTTensor | `imageToDTTensor()` |
| **Canvas image (img2img)** | DTTensor | `imageToDTTensor()` |
| **Mask image (inpainting)** | DTTensor | `imageToDTTensor()` |
| **Result images returned** | DTTensor | `dtTensorToImage()` |
| **Preview images returned** | DTTensor | `dtTensorToImage()` |

### Common Pitfalls

1. **Sending PNG data instead of DTTensor**: The server will crash or return no results if you send PNG/JPEG data where DTTensor is expected.

2. **Saving raw result data as image files**: Result images are DTTensor format. Saving them directly as `.png` files will create corrupted files. Always convert with `dtTensorToImage()` first.

3. **NaN/Infinity in tensor data**: The `dtTensorToImage()` function handles NaN/infinity Float16 values by defaulting to mid-gray. This prevents crashes when processing malformed data.

### Example: Complete img2img Flow

```swift
// 1. Load source image
let sourceImage = PlatformImage(contentsOf: sourceURL)!  // NSImage on macOS, UIImage on iOS

// 2. Convert to DTTensor for sending
let canvasData = try ImageHelpers.imageToDTTensor(sourceImage, forceRGB: true)

// 3. Generate with img2img
let results = try await service.generateImage(
    prompt: "Transform this image",
    configuration: configData,
    image: canvasData  // DTTensor format, NOT PNG
)

// 4. Convert results back to images
for resultData in results {
    let resultImage = try ImageHelpers.dtTensorToImage(resultData)
    // Now you can save as PNG, display, etc.
}
```

## Configuration JSON Handling

Draw Things can export its configuration as JSON. Here is a complete example:

```json
{
  "aestheticScore": 6,
  "batchCount": 10,
  "batchSize": 1,
  "causalInference": 0,
  "causalInferencePad": 0,
  "cfgZeroInitSteps": 0,
  "cfgZeroStar": false,
  "clipLText": null,
  "clipSkip": 1,
  "clipWeight": 1,
  "compressionArtifacts": "disabled",
  "compressionArtifactsQuality": 43.1,
  "controls": [],
  "cropLeft": 0,
  "cropTop": 0,
  "decodingTileHeight": 640,
  "decodingTileOverlap": 128,
  "decodingTileWidth": 640,
  "diffusionTileHeight": 1024,
  "diffusionTileOverlap": 128,
  "diffusionTileWidth": 1024,
  "faceRestoration": null,
  "fps": 5,
  "guidanceEmbed": 3.5,
  "guidanceScale": 1,
  "guidingFrameNoise": 0.02,
  "height": 1280,
  "hiresFix": false,
  "hiresFixHeight": 1024,
  "hiresFixStrength": 0.7,
  "hiresFixWidth": 1024,
  "id": 0,
  "imageGuidanceScale": 1.5,
  "imagePriorSteps": 5,
  "loras": [
    {
      "file": "zit_natalie_illustrated_lora_f16.ckpt",
      "mode": "all",
      "weight": 0.65
    }
  ],
  "maskBlur": 1.5,
  "maskBlurOutset": 0,
  "model": "z_image_turbo_1.0_q8p.ckpt",
  "motionScale": 127,
  "negativeAestheticScore": 2.5,
  "negativeOriginalImageHeight": 640,
  "negativeOriginalImageWidth": 640,
  "negativePromptForImagePrior": true,
  "numFrames": 14,
  "openClipGText": null,
  "originalImageHeight": 1280,
  "originalImageWidth": 1280,
  "preserveOriginalAfterInpaint": true,
  "refinerModel": null,
  "refinerStart": 0.85,
  "resolutionDependentShift": false,
  "sampler": 17,
  "seed": 945446116,
  "seedMode": 2,
  "separateClipL": false,
  "separateOpenClipG": false,
  "separateT5": false,
  "sharpness": 0,
  "shift": 3,
  "speedUpWithGuidanceEmbed": true,
  "stage2Guidance": 1,
  "stage2Shift": 1,
  "stage2Steps": 10,
  "startFrameGuidance": 1,
  "steps": 8,
  "stochasticSamplingGamma": 0.3,
  "strength": 1,
  "t5TextEncoder": true,
  "targetImageHeight": 1280,
  "targetImageWidth": 1280,
  "teaCache": false,
  "teaCacheEnd": -1,
  "teaCacheMaxSkipSteps": 3,
  "teaCacheStart": 5,
  "teaCacheThreshold": 0.2,
  "tiledDecoding": false,
  "tiledDiffusion": false,
  "upscaler": null,
  "upscalerScaleFactor": 0,
  "width": 1280,
  "zeroNegativePrompt": false
}
```

See `./Examples/ConfigfromJSON.swift` for a complete function that parses a Draw Things JSON export into a `DrawThingsConfiguration`.

When parsing Draw Things configuration JSON exports, be aware of these edge cases:

### Empty String vs Nil

Draw Things exports empty optional fields as empty strings (`""`) or `null`. Treat empty strings as nil for these fields:

| Field | Empty String Means |
|-------|-------------------|
| `upscaler` | No upscaler (use default) |
| `faceRestoration` | No face restoration |
| `refinerModel` | No refiner model |

**Warning**: If you pass an empty string for `upscaler`, Draw Things will attempt to load it as a model name and crash.

### String Enums in JSON

Several fields are exported as strings in JSON but map to integer enums in the FlatBuffer protocol:

**LoRA mode** (`loras[].mode`):

| JSON String | Enum Value |
|-------------|-----------|
| `"all"` | `0` |
| `"base"` | `1` |
| `"refiner"` | `2` |

**Control importance** (`controls[].controlImportance`):

| JSON String | Enum Value |
|-------------|-----------|
| `"balanced"` | `0` |
| `"prompt"` | `1` |
| `"control"` | `2` |

**Compression artifacts** (`compressionArtifacts`):

| JSON String | Enum Value |
|-------------|-----------|
| `"disabled"` | `0` |
| `"h264"` | `1` |
| `"h265"` | `2` |
| `"jpeg"` | `3` |

### Sampler Values

Samplers are represented as integers in the configuration:

| Sampler Name | Integer Value |
|--------------|---------------|
| `dpmpp2mkarras` | `0` |
| `eulera` | `1` |
| `ddim` | `2` |
| `plms` | `3` |
| `dpmppsdekarras` | `4` |
| `unipc` | `5` |
| `lcm` | `6` |
| `eulerasubstep` | `7` |
| `dpmppsdesubstep` | `8` |
| `tcd` | `9` |
| `euleratrailing` | `10` |
| `dpmppsdetrailing` | `11` |
| `dpmpp2mays` | `12` |
| `euleraays` | `13` |
| `dpmppsdeays` | `14` |
| `dpmpp2mtrailing` | `15` |
| `ddimtrailing` | `16` |
| `unipctrailing` | `17` |
| `unipcays` | `18` |
| `tcdtrailing` | `19` |

### Tile Dimensions

Tile dimensions (`diffusionTileWidth`, `decodingTileHeight`, etc.) are in **pixels** in the JSON export. The `DrawThingsConfiguration` accepts pixel values and converts to 64-pixel units internally during FlatBuffer serialization.

## Installation

### Swift Package Manager

Add DrawThingsClient to your project via Xcode:

1. File → Add Package Dependencies...
2. Enter the repository URL
3. Select the version/branch you want to use

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client", from: "1.2.5")
]
```

## Quick Start

### API Levels

This library provides two API levels:

| API | Class | Use Case |
|-----|-------|----------|
| **High-level** | `DrawThingsClient` | Simple integration, handles DTTensor conversion automatically, supports hints/moodboard, returns `[PlatformImage]` |
| **Low-level** | `DrawThingsService` | Full control, requires manual DTTensor conversion, supports all parameters including preview callbacks, returns `[Data]` |

For most use cases, start with `DrawThingsClient`. Use `DrawThingsService` when you need:
- Progress callbacks with preview images
- Custom handling of raw tensor data
- Access to all generation parameters (contents, override, scaleFactor)

### Basic Usage

```swift
import DrawThingsClient
import SwiftUI

struct ContentView: View {
    @StateObject private var client: DrawThingsClient
    @State private var prompt = "A beautiful landscape"
    
    init() {
        do {
            let client = try DrawThingsClient(address: "localhost:7859")
            _client = StateObject(wrappedValue: client)
        } catch {
            fatalError("Failed to create client: \(error)")
        }
    }
    
    var body: some View {
        VStack {
            TextField("Enter prompt", text: $prompt)
            
            Button("Generate") {
                Task {
                    await generateImage()
                }
            }
            .disabled(!client.isConnected)
            
            if let progress = client.currentProgress {
                Text(progress.stage.description)
                ProgressView()
            }
        }
        .task {
            await client.connect()
        }
    }
    
    private func generateImage() async {
        do {
            let config = DrawThingsConfiguration(
                width: 512,
                height: 512,
                steps: 20
            )
            
            let images = try await client.generateImage(
                prompt: prompt,
                configuration: config
            )
            
            // Use generated images...
        } catch {
            print("Generation failed: \(error)")
        }
    }
}
```

### Configuration Options

```swift
let config = DrawThingsConfiguration(
    width: 1024,
    height: 1024,
    steps: 30,
    model: "sd_xl_base_1.0.safetensors",
    sampler: .eulera,
    guidanceScale: 7.5,
    seed: 12345,
    clipSkip: 2
)
```
See `./Examples/ConfigfromJSON.swift` within this project for a usable function which populates a `DrawThingsConfiguration` from a Draw Things JSON configuration string.

### Shared Secret Authentication

If the Draw Things server requires a shared secret, pass it with the generation request:

```swift
// High-level API
let images = try await client.generateImage(
    prompt: "A beautiful landscape",
    configuration: config,
    sharedSecret: "my-secret-key"
)

// Low-level API
let resultData = try await service.generateImage(
    prompt: "A beautiful landscape",
    configuration: configData,
    sharedSecret: "my-secret-key"
)
```

### Image-to-Image Generation

Using the high-level `DrawThingsClient` API (handles DTTensor conversion automatically):

```swift
let inputImage = NSImage(named: "input.jpg")!

let images = try await client.generateImage(
    prompt: "Transform this into a watercolor painting",
    configuration: config,
    image: inputImage  // NSImage - converted to DTTensor internally
)
```

Using the lower-level `DrawThingsService` API (requires manual DTTensor conversion):

```swift
let inputImage = NSImage(named: "input.jpg")!
let imageData = try ImageHelpers.imageToDTTensor(inputImage, forceRGB: true)
let configData = try config.toFlatBufferData()

let resultData = try await service.generateImage(
    prompt: "Transform this into a watercolor painting",
    configuration: configData,
    image: imageData  // Must be DTTensor format
)

// Convert results back to NSImage
let images = try resultData.map { try ImageHelpers.dtTensorToImage($0) }
```

### Inpainting with Mask

Using the high-level `DrawThingsClient` API:

```swift
let inputImage = NSImage(named: "photo.jpg")!
let maskImage = NSImage(named: "mask.png")!

let images = try await client.generateImage(
    prompt: "A cat sitting in the masked area",
    configuration: config,
    image: inputImage,
    mask: maskImage
)
```

Using the lower-level `DrawThingsService` API:

```swift
let inputImage = NSImage(named: "photo.jpg")!
let maskImage = NSImage(named: "mask.png")!

let imageData = try ImageHelpers.imageToDTTensor(inputImage, forceRGB: true)
let maskData = try ImageHelpers.imageToDTTensor(maskImage, forceRGB: true)
let configData = try config.toFlatBufferData()

let resultData = try await service.generateImage(
    prompt: "A cat sitting in the masked area",
    configuration: configData,
    image: imageData,
    mask: maskData
)

let images = try resultData.map { try ImageHelpers.dtTensorToImage($0) }
```

### Moodboard / Reference Images

Use moodboard (also known as "shuffle") to provide reference images that influence the generation. This is particularly useful with models like Qwen Image Edit. Both `DrawThingsClient` and `DrawThingsService` support hints:

```swift
// Single reference image
let referenceImage = NSImage(named: "style_reference.jpg")!
let referenceData = try ImageHelpers.imageToDTTensor(referenceImage, forceRGB: true)

var tensorAndWeight = TensorAndWeight()
tensorAndWeight.tensor = referenceData
tensorAndWeight.weight = 1.0  // Weight from 0.0 to 1.0

var hint = HintProto()
hint.hintType = "shuffle"  // Use "shuffle" for moodboard/reference images
hint.tensors = [tensorAndWeight]

// Using DrawThingsClient (high-level)
let images = try await client.generateImage(
    prompt: "A woman wearing a blue dress",
    configuration: config,
    hints: [hint]
)

// Using DrawThingsService (low-level)
let resultData = try await service.generateImage(
    prompt: "A woman wearing a blue dress",
    negativePrompt: "",
    configuration: configData,
    hints: [hint]
)
```

Multiple reference images can be provided by adding more hints to the array:

```swift
// Multiple reference images
var hints: [HintProto] = []

let referenceImages = [
    NSImage(named: "dress_ref.jpg")!,
    NSImage(named: "style_ref.jpg")!,
    NSImage(named: "color_ref.jpg")!
]

for refImage in referenceImages {
    let imageData = try ImageHelpers.imageToDTTensor(refImage, forceRGB: true)

    var tensorAndWeight = TensorAndWeight()
    tensorAndWeight.tensor = imageData
    tensorAndWeight.weight = 1.0

    var hint = HintProto()
    hint.hintType = "shuffle"
    hint.tensors = [tensorAndWeight]

    hints.append(hint)
}

let images = try await service.generateImage(
    prompt: "Combine elements from the reference images",
    negativePrompt: "",
    configuration: configData,
    hints: hints
)
```

**Note:** The moodboard feature works best with models that are designed to use reference images. See also the [HintBuilder](#hintbuilder) section below for a simpler way to construct hints.

### ControlNet

ControlNet allows you to guide image generation using control images (such as depth maps, poses, or reference faces). The control image is provided as a hint, and the ControlNet model configuration specifies how to use it:

```swift
// Create ControlNet configuration
let controlConfig = ControlConfig(
    file: "pulid_flux_v0.9.1.safetensors",  // ControlNet model file
    weight: 1.0,                             // Control strength (0.0 to 2.0)
    guidanceStart: 0.0,                      // When to start applying control (0.0 = beginning)
    guidanceEnd: 1.0,                        // When to stop applying control (1.0 = end)
    controlMode: "balanced"                  // "balanced", "prompt", or "control"
)

// Create configuration with ControlNet
let config = DrawThingsConfiguration(
    width: 1024,
    height: 1024,
    steps: 30,
    model: "flux1_chroma_v48.safetensors",
    controls: [controlConfig]
)

// Prepare the control image (e.g., a face for PuLID)
let controlImage = NSImage(named: "reference_face.jpg")!
let controlImageData = try ImageHelpers.imageToDTTensor(controlImage, forceRGB: true)

var tensorAndWeight = TensorAndWeight()
tensorAndWeight.tensor = controlImageData
tensorAndWeight.weight = 1.0

var hint = HintProto()
hint.hintType = "shuffle"  // Control images are sent as hints
hint.tensors = [tensorAndWeight]

// Generate with ControlNet
let images = try await service.generateImage(
    prompt: "A full-body portrait of a character",
    negativePrompt: "",
    configuration: try config.toFlatBufferData(),
    hints: [hint]
)
```

**ControlNet Parameters:**

- `file`: The ControlNet model filename (must be compatible with the base model)
- `weight`: Control strength - higher values give stronger control (default: 1.0, range: 0.0-2.0)
- `guidanceStart`: When to start applying control during generation (0.0 = first step)
- `guidanceEnd`: When to stop applying control (1.0 = last step)
- `controlMode`:
  - `"balanced"`: Equal weight between prompt and control
  - `"prompt"`: Favor the text prompt more
  - `"control"`: Favor the control image more

**Common ControlNet Types:**
- **PuLID**: Face/character consistency (use with portrait/face images)
- **Depth**: Control composition with depth maps
- **Canny**: Edge-based control
- **Pose**: Human pose control (OpenPose)
- **Scribble**: Sketch-based control

### HintBuilder

The `HintBuilder` class provides a convenient fluent API for constructing hints without manually creating `HintProto` and `TensorAndWeight` objects. It accepts raw image data (PNG/JPEG) and handles DTTensor conversion automatically.

```swift
// Single moodboard image
let imageData = try Data(contentsOf: imageURL)
let hints = HintBuilder()
    .addMoodboardImage(imageData, weight: 1.0)
    .build()

let images = try await client.generateImage(
    prompt: "A woman wearing a blue dress",
    configuration: config,
    hints: hints
)
```

Multiple images and different hint types can be combined:

```swift
let refData = try Data(contentsOf: referenceURL)
let depthData = try Data(contentsOf: depthMapURL)
let edgeData = try Data(contentsOf: cannyURL)

let hints = HintBuilder()
    .addMoodboardImage(refData)
    .addDepthMap(depthData, weight: 0.8)
    .addCannyEdges(edgeData, weight: 0.5)
    .build()
```

Multiple moodboard images at once:

```swift
let imageFiles = [image1Data, image2Data, image3Data]
let hints = HintBuilder()
    .addMoodboardImages(imageFiles, weight: 1.0)
    .build()
```

**Available typed methods:**

| Method | Hint Type | Use Case |
|--------|-----------|----------|
| `addMoodboardImage(_:weight:)` | `shuffle` | Reference/style images |
| `addMoodboardImages(_:weight:)` | `shuffle` | Multiple reference images |
| `addDepthMap(_:weight:)` | `depth` | Depth-based composition control |
| `addPose(_:weight:)` | `pose` | Human pose control (OpenPose) |
| `addCannyEdges(_:weight:)` | `canny` | Edge-based control |
| `addScribble(_:weight:)` | `scribble` | Sketch-based control |
| `addColorReference(_:weight:)` | `color` | Color palette control |
| `addLineArt(_:weight:)` | `lineart` | Line art control |

For hint types not covered by the typed methods, use `addHint(type:imageData:weight:)` with either a `HintType` enum value or a custom string:

```swift
let hints = HintBuilder()
    .addHint(type: .tile, imageData: tileData)
    .addHint(type: "custom_type", imageData: customData)
    .build()
```

**Available hint types** (`HintType` enum): `shuffle`, `depth`, `pose`, `canny`, `scribble`, `color`, `lineart`, `softedge`, `seg`, `inpaint`, `ip2p`, `mlsd`, `tile`, `blur`, `lowquality`, `gray`, `custom`

### Using LoRAs

LoRAs (Low-Rank Adaptations) allow you to modify the generation style or add specific concepts:

```swift
// Create LoRA configurations
let loraConfig1 = LoRAConfig(
    file: "style_lora.safetensors",
    weight: 0.8,
    mode: "all"  // "all", "base", or "refiner"
)

let loraConfig2 = LoRAConfig(
    file: "concept_lora.safetensors",
    weight: 1.0,
    mode: "all"
)

// Create configuration with LoRAs
let config = DrawThingsConfiguration(
    width: 1024,
    height: 1024,
    steps: 30,
    model: "sd_xl_base_1.0.safetensors",
    loras: [loraConfig1, loraConfig2]
)

let images = try await client.generateImage(
    prompt: "A beautiful landscape",
    configuration: config
)
```

**LoRA Parameters:**
- `file`: The LoRA model filename (must be compatible with base model version)
- `weight`: LoRA influence strength (typically 0.0-1.0, but can go higher)
- `mode`: When to apply the LoRA
  - `"all"`: Apply to all stages
  - `"base"`: Apply only during base model generation
  - `"refiner"`: Apply only during refiner stage

### Video Generation

DrawThingsClient supports video/animation generation with models that support temporal generation (e.g., Stable Video Diffusion, AnimateDiff, etc.). Video frames are generated on the server and returned sequentially as individual images.

#### Text-to-Video

```swift
// Configure video generation parameters
let config = DrawThingsConfiguration(
    width: 1024,
    height: 576,
    steps: 30,
    model: "svd_xt_1.1.safetensors",
    numFrames: 25                // Number of frames to generate
)

let frames = try await client.generateImage(
    prompt: "A cat walking through a garden",
    configuration: config
)

// frames is an array of NSImage, one for each frame
print("Generated \(frames.count) frames")

// Process frames (e.g., save to disk, create video file, etc.)
for (index, frame) in frames.enumerated() {
    // Save frame_001.png, frame_002.png, etc.
    saveFrame(frame, index: index)
}
```

#### Image-to-Video

Generate a video starting from a base image:

```swift
let startImage = NSImage(named: "start_frame.jpg")!

let config = DrawThingsConfiguration(
    width: 1024,
    height: 576,
    steps: 30,
    model: "svd_xt_1.1.safetensors",
    numFrames: 25,
    strength: 0.8               // How much to transform the input image
)

let frames = try await client.generateImage(
    prompt: "Animate this image",
    configuration: config,
    image: startImage
)

print("Generated \(frames.count) video frames from input image")
```

**Video Generation Parameters:**

- `numFrames`: Number of frames to generate (e.g., 14, 25, 81)
- `startFrameGuidance`: CFG scale for the first frame guidance (default: 1.0)

**Important Notes:**

- **Sequential Frame Delivery**: The gRPC server generates all frames, then sends them back **one at a time** in sequence. The `generateImage()` method will return an array with all frames once complete.
- **Processing Time**: Video generation takes significantly longer than single images due to generating multiple frames.
- **Frame Count**: Higher frame counts result in longer videos but also longer generation times.
- **Memory Usage**: All frames are held in memory as NSImage objects. For long videos (100+ frames), consider processing and saving frames as they arrive.

**Example: Saving Video Frames**

```swift
let frames = try await client.generateImage(
    prompt: "A serene ocean sunset with gentle waves",
    configuration: config
)

// Save frames as sequential PNG files
for (index, frame) in frames.enumerated() {
    let filename = String(format: "frame_%03d.png", index + 1)
    let url = outputDirectory.appendingPathComponent(filename)

    if let tiffData = frame.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try pngData.write(to: url)
    }
}

print("Saved \(frames.count) frames to \(outputDirectory.path)")

// Use external tools to create video from frames:
// ffmpeg -framerate 8 -i frame_%03d.png -c:v libx264 -pix_fmt yuv420p output.mp4
```

## Cross-Platform Support

DrawThingsClient supports both macOS and iOS. The library provides cross-platform abstractions for image handling:

### Platform Types

| Type | macOS | iOS |
|------|-------|-----|
| `PlatformImage` | `NSImage` | `UIImage` |
| `PlatformColor` | `NSColor` | `UIColor` |

### Cross-Platform Image Helpers

```swift
// Works on both macOS and iOS
let image: PlatformImage = ...

// Convert to DTTensor
let tensorData = try ImageHelpers.imageToDTTensor(image, forceRGB: true)

// Convert from DTTensor
let resultImage = try ImageHelpers.dtTensorToImage(tensorData)

// Save to file (PNG or JPEG)
try ImageHelpers.saveImage(image, to: outputURL, format: .png)
try ImageHelpers.saveImage(image, to: jpegURL, format: .jpeg, jpegQuality: 0.85)

// Other cross-platform utilities
let resized = ImageHelpers.resizeImage(image, to: CGSize(width: 512, height: 512))
let scaled = ImageHelpers.scaleImageToCanvas(image, canvasWidth: 1024, canvasHeight: 1024, backgroundColor: nil)
let hasAlpha = ImageHelpers.hasTransparency(image)
```

### Legacy macOS Methods

For backward compatibility, the following deprecated methods are still available on macOS:
- `nsImageToDTTensor()` → use `imageToDTTensor()` instead
- `dtTensorToNSImage()` → use `dtTensorToImage()` instead
- `dataToNSImage()` → use `dataToImage()` instead

---

## Architecture

DrawThingsClient is built on top of:

- **gRPC Swift**: Modern gRPC client with async/await support
- **SwiftProtobuf**: Type-safe protocol buffer implementation
- **SwiftNIO**: High-performance networking
- **FlatBuffers**: Configuration serialization
- **fpzip**: Floating-point tensor decompression (via swift-fpzip-support)

The framework provides two main interfaces:

1. **DrawThingsService**: Low-level async actor for direct gRPC communication
2. **DrawThingsClient**: High-level ObservableObject for SwiftUI integration

## Development

### Building from Source

1. Clone the repository
2. Install dependencies:
   ```bash
   brew install protoc-gen-grpc-swift swift-protobuf
   ```
3. Generate protobuf code (if needed):
   ```bash
   ./generate_protos.sh
   ```
4. Build:
   ```bash
   swift build
   ```

### Running Tests

```bash
swift test
```

### Example App

The repository includes a complete SwiftUI example application:

```bash
cd Examples/SwiftUIExample
swift run
```

## API Reference

### DrawThingsClient (SwiftUI)

- `init(address: String, useTLS: Bool = true)`: Create a new client
- `connect() async`: Connect to the Draw Things server
- `generateImage(prompt:negativePrompt:configuration:image:mask:hints:sharedSecret:) async throws -> [PlatformImage]`: Generate images with progress tracking
- `generateImageAndAudio(prompt:negativePrompt:configuration:image:mask:sharedSecret:) async throws -> GenerationOutput`: Generate images and audio (LTX-2)
- `@Published var isConnected`: Connection status
- `@Published var currentProgress`: Current generation progress

### DrawThingsService (Low-level)

- `echo(name:) async throws -> EchoReply`: Server health check
- `generateImage(prompt:negativePrompt:configuration:image:mask:hints:contents:override:scaleFactor:sharedSecret:progressHandler:previewHandler:audioHandler:) async throws -> [Data]`: Generate images with full control
- `checkFilesExist(files:filesWithHash:) async throws -> FileExistenceResponse`: Check file existence

### Configuration

- `DrawThingsConfiguration`: Image generation parameters
- `SamplerType`: Available sampling methods
- `ImageHelpers`: Image conversion utilities

## Error Handling

```swift
do {
    let images = try await client.generateImage(prompt: "test")
} catch DrawThingsError.connectionFailed {
    // Handle connection issues
} catch DrawThingsError.generationFailed(let reason) {
    // Handle generation errors
} catch {
    // Handle other errors
}
```

## Logging & Debugging

DrawThingsClient uses Apple's unified logging system (`os.log`) for diagnostic output. By default, logging is disabled in production.

### Enable Logging

To enable logging for debugging:

```swift
import DrawThingsClient

// Enable debug logging
DrawThingsClientLogger.minimumLevel = .debug

// Or set a higher threshold
DrawThingsClientLogger.minimumLevel = .info  // Only info and above
```

### Log Levels

- `.debug` - Detailed diagnostic information (request/response data, sizes, etc.)
- `.info` - General informational messages
- `.notice` - Significant events
- `.error` - Error conditions
- `.fault` - Critical failures
- `.none` - Disable all logging (default)

### Viewing Logs

Logs can be viewed in:
- **Console.app** on macOS (filter by subsystem: `com.drawthings.kit`)
- **Xcode Debug Console** during development
- Terminal using: `log stream --predicate 'subsystem == "com.drawthings.kit"'`

### Disable Emoji

If you prefer plain log messages without emoji prefixes:

```swift
DrawThingsClientLogger.useEmoji = false
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Credits

This Swift framework is a port of the original TypeScript implementation by KC Jerrell:
- **Original Project**: [dt-grpc-ts](https://github.com/kcjerrell/dt-grpc-ts)
- **Author**: KC Jerrell ([@kcjerrell](https://github.com/kcjerrell))

Special thanks to KC for pioneering the TypeScript gRPC client for Draw Things, which served as the foundation for this Swift implementation.

## Compatibility

This framework maintains API compatibility with the Draw Things gRPC server protocol.
