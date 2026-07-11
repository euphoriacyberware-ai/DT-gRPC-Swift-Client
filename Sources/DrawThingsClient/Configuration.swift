//
//  Configuration.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import FlatBuffers

public struct LoRAConfig: Sendable {
    public let file: String
    public let weight: Float
    public let mode: LoRAMode

    public init(file: String, weight: Float = 1.0, mode: LoRAMode = .all) {
        self.file = file
        self.weight = weight
        self.mode = mode
    }
}

public struct ControlConfig: Sendable {
    public let file: String
    public let weight: Float
    public let guidanceStart: Float
    public let guidanceEnd: Float
    public let controlMode: ControlMode

    public init(file: String, weight: Float = 1.0, guidanceStart: Float = 0.0, guidanceEnd: Float = 1.0, controlMode: ControlMode = .balanced) {
        self.file = file
        self.weight = weight
        self.guidanceStart = guidanceStart
        self.guidanceEnd = guidanceEnd
        self.controlMode = controlMode
    }
}

public struct DrawThingsConfiguration: Sendable {
    // Core parameters (width/height must be multiples of 64)
    public var width: Int32 = 512 {
        didSet { width = (width / 64) * 64 }
    }
    public var height: Int32 = 512 {
        didSet { height = (height / 64) * 64 }
    }
    public var steps: Int32
    public var model: String
    public var sampler: SamplerType
    public var guidanceScale: Float
    public var seed: Int64?
    public var clipSkip: Int32
    public var loras: [LoRAConfig]
    public var controls: [ControlConfig]
    public var shift: Float

    // Batch parameters
    public var batchCount: Int32
    public var batchSize: Int32
    public var strength: Float

    // Guidance parameters
    public var imageGuidanceScale: Float
    public var clipWeight: Float
    public var guidanceEmbed: Float
    public var speedUpWithGuidanceEmbed: Bool
    public var cfgZeroStar: Bool
    public var cfgZeroInitSteps: Int32

    // Compression parameters
    public var compressionArtifacts: CompressionMethod
    public var compressionArtifactsQuality: Float

    // Mask/Inpaint parameters
    public var maskBlur: Float
    public var maskBlurOutset: Int32
    public var preserveOriginalAfterInpaint: Bool
    public var enableInpainting: Bool  // When true, adds inpaint control to enable mask-based inpainting

    // Quality parameters
    public var sharpness: Float
    public var stochasticSamplingGamma: Float
    public var aestheticScore: Float
    public var negativeAestheticScore: Float

    // Image prior parameters
    public var negativePromptForImagePrior: Bool
    public var imagePriorSteps: Int32

    // Crop/Size parameters
    public var cropTop: Int32
    public var cropLeft: Int32
    public var originalImageHeight: Int32
    public var originalImageWidth: Int32
    public var targetImageHeight: Int32
    public var targetImageWidth: Int32
    public var negativeOriginalImageHeight: Int32
    public var negativeOriginalImageWidth: Int32

    // Upscaler parameters
    public var upscalerScaleFactor: Int32

    // Text encoder parameters
    public var resolutionDependentShift: Bool
    public var t5TextEncoder: Bool
    public var separateClipL: Bool
    public var separateOpenClipG: Bool
    public var separateT5: Bool

    // Tiled parameters
    public var tiledDiffusion: Bool
    public var diffusionTileWidth: Int32
    public var diffusionTileHeight: Int32
    public var diffusionTileOverlap: Int32
    public var tiledDecoding: Bool
    public var decodingTileWidth: Int32
    public var decodingTileHeight: Int32
    public var decodingTileOverlap: Int32

    // HiRes Fix parameters (width/height must be multiples of 64)
    public var hiresFix: Bool
    public var hiresFixWidth: Int32 = 0 {
        didSet { hiresFixWidth = (hiresFixWidth / 64) * 64 }
    }
    public var hiresFixHeight: Int32 = 0 {
        didSet { hiresFixHeight = (hiresFixHeight / 64) * 64 }
    }
    public var hiresFixStrength: Float

    // Stage 2 parameters
    public var stage2Steps: Int32
    public var stage2Guidance: Float
    public var stage2Shift: Float

    // TEA Cache parameters
    public var teaCache: Bool
    public var teaCacheStart: Int32
    public var teaCacheEnd: Int32
    public var teaCacheThreshold: Float
    public var teaCacheMaxSkipSteps: Int32

    // Causal inference parameters
    public var causalInferenceEnabled: Bool
    public var causalInference: Int32
    public var causalInferencePad: Int32

    // Video parameters
    public var fps: Int32
    public var motionScale: Int32
    public var guidingFrameNoise: Float
    public var startFrameGuidance: Float
    public var numFrames: Int32

    // Refiner parameters
    public var refinerModel: String?
    public var refinerStart: Float
    public var zeroNegativePrompt: Bool

    // Upscaler parameters
    public var upscaler: String?

    // Face restoration
    public var faceRestoration: String?

    // Configuration name
    public var name: String?

    // Separate text encoder prompts
    public var clipLText: String?
    public var openClipGText: String?
    public var t5Text: String?

    // Seed mode
    public var seedMode: Int32

    public init(
        width: Int32 = 512,
        height: Int32 = 512,
        steps: Int32 = 20,
        model: String = "sd_xl_base_1.0.safetensors",
        sampler: SamplerType = .dpmpp2mkarras,
        guidanceScale: Float = 7.0,
        seed: Int64? = nil,
        clipSkip: Int32 = 1,
        loras: [LoRAConfig] = [],
        controls: [ControlConfig] = [],
        shift: Float = 1.0,
        batchCount: Int32 = 1,
        batchSize: Int32 = 1,
        strength: Float = 1.0,
        imageGuidanceScale: Float = 1.5,
        clipWeight: Float = 1.0,
        guidanceEmbed: Float = 3.5,
        speedUpWithGuidanceEmbed: Bool = true,
        cfgZeroStar: Bool = false,
        cfgZeroInitSteps: Int32 = 0,
        compressionArtifacts: CompressionMethod = .disabled,
        compressionArtifactsQuality: Float = 43.1,
        maskBlur: Float = 1.5,
        maskBlurOutset: Int32 = 0,
        preserveOriginalAfterInpaint: Bool = true,
        enableInpainting: Bool = false,
        sharpness: Float = 0.0,
        stochasticSamplingGamma: Float = 0.3,
        aestheticScore: Float = 6.0,
        negativeAestheticScore: Float = 2.5,
        negativePromptForImagePrior: Bool = true,
        imagePriorSteps: Int32 = 5,
        cropTop: Int32 = 0,
        cropLeft: Int32 = 0,
        originalImageHeight: Int32 = 0,
        originalImageWidth: Int32 = 0,
        targetImageHeight: Int32 = 0,
        targetImageWidth: Int32 = 0,
        negativeOriginalImageHeight: Int32 = 0,
        negativeOriginalImageWidth: Int32 = 0,
        upscalerScaleFactor: Int32 = 0,
        resolutionDependentShift: Bool = true,
        t5TextEncoder: Bool = true,
        separateClipL: Bool = false,
        separateOpenClipG: Bool = false,
        separateT5: Bool = false,
        tiledDiffusion: Bool = false,
        diffusionTileWidth: Int32 = 1024,
        diffusionTileHeight: Int32 = 1024,
        diffusionTileOverlap: Int32 = 128,
        tiledDecoding: Bool = false,
        decodingTileWidth: Int32 = 640,
        decodingTileHeight: Int32 = 640,
        decodingTileOverlap: Int32 = 128,
        hiresFix: Bool = false,
        hiresFixWidth: Int32 = 0,
        hiresFixHeight: Int32 = 0,
        hiresFixStrength: Float = 0.7,
        stage2Steps: Int32 = 10,
        stage2Guidance: Float = 1.0,
        stage2Shift: Float = 1.0,
        teaCache: Bool = false,
        teaCacheStart: Int32 = 5,
        teaCacheEnd: Int32 = -1,
        teaCacheThreshold: Float = 0.06,
        teaCacheMaxSkipSteps: Int32 = 3,
        causalInferenceEnabled: Bool = false,
        causalInference: Int32 = 3,
        causalInferencePad: Int32 = 0,
        fps: Int32 = 5,
        motionScale: Int32 = 127,
        guidingFrameNoise: Float = 0.02,
        startFrameGuidance: Float = 1.0,
        numFrames: Int32 = 14,
        refinerModel: String? = nil,
        refinerStart: Float = 0.85,
        zeroNegativePrompt: Bool = false,
        upscaler: String? = nil,
        faceRestoration: String? = nil,
        name: String? = nil,
        clipLText: String? = nil,
        openClipGText: String? = nil,
        t5Text: String? = nil,
        seedMode: Int32 = 2
    ) {
        self.width = width
        self.height = height
        self.steps = steps
        self.model = model
        self.sampler = sampler
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.clipSkip = clipSkip
        self.loras = loras
        self.controls = controls
        self.shift = shift
        self.batchCount = batchCount
        self.batchSize = batchSize
        self.strength = strength
        self.imageGuidanceScale = imageGuidanceScale
        self.clipWeight = clipWeight
        self.guidanceEmbed = guidanceEmbed
        self.speedUpWithGuidanceEmbed = speedUpWithGuidanceEmbed
        self.cfgZeroStar = cfgZeroStar
        self.cfgZeroInitSteps = cfgZeroInitSteps
        self.compressionArtifacts = compressionArtifacts
        self.compressionArtifactsQuality = compressionArtifactsQuality
        self.maskBlur = maskBlur
        self.maskBlurOutset = maskBlurOutset
        self.preserveOriginalAfterInpaint = preserveOriginalAfterInpaint
        self.enableInpainting = enableInpainting
        self.sharpness = sharpness
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.aestheticScore = aestheticScore
        self.negativeAestheticScore = negativeAestheticScore
        self.negativePromptForImagePrior = negativePromptForImagePrior
        self.imagePriorSteps = imagePriorSteps
        self.cropTop = cropTop
        self.cropLeft = cropLeft
        self.originalImageHeight = originalImageHeight
        self.originalImageWidth = originalImageWidth
        self.targetImageHeight = targetImageHeight
        self.targetImageWidth = targetImageWidth
        self.negativeOriginalImageHeight = negativeOriginalImageHeight
        self.negativeOriginalImageWidth = negativeOriginalImageWidth
        self.upscalerScaleFactor = upscalerScaleFactor
        self.resolutionDependentShift = resolutionDependentShift
        self.t5TextEncoder = t5TextEncoder
        self.separateClipL = separateClipL
        self.separateOpenClipG = separateOpenClipG
        self.separateT5 = separateT5
        self.tiledDiffusion = tiledDiffusion
        self.diffusionTileWidth = diffusionTileWidth
        self.diffusionTileHeight = diffusionTileHeight
        self.diffusionTileOverlap = diffusionTileOverlap
        self.tiledDecoding = tiledDecoding
        self.decodingTileWidth = decodingTileWidth
        self.decodingTileHeight = decodingTileHeight
        self.decodingTileOverlap = decodingTileOverlap
        self.hiresFix = hiresFix
        self.hiresFixWidth = hiresFixWidth
        self.hiresFixHeight = hiresFixHeight
        self.hiresFixStrength = hiresFixStrength
        self.stage2Steps = stage2Steps
        self.stage2Guidance = stage2Guidance
        self.stage2Shift = stage2Shift
        self.teaCache = teaCache
        self.teaCacheStart = teaCacheStart
        self.teaCacheEnd = teaCacheEnd
        self.teaCacheThreshold = teaCacheThreshold
        self.teaCacheMaxSkipSteps = teaCacheMaxSkipSteps
        self.causalInferenceEnabled = causalInferenceEnabled
        self.causalInference = causalInference
        self.causalInferencePad = causalInferencePad
        self.fps = fps
        self.motionScale = motionScale
        self.guidingFrameNoise = guidingFrameNoise
        self.startFrameGuidance = startFrameGuidance
        self.numFrames = numFrames
        self.refinerModel = refinerModel
        self.refinerStart = refinerStart
        self.zeroNegativePrompt = zeroNegativePrompt
        self.upscaler = upscaler
        self.faceRestoration = faceRestoration
        self.name = name
        self.clipLText = clipLText
        self.openClipGText = openClipGText
        self.t5Text = t5Text
        self.seedMode = seedMode
    }

    public func toFlatBufferData() throws -> Data {
        // Create GenerationConfigurationT object
        let configT = GenerationConfigurationT()

        // Convert width/height to units of 64 pixels as per FlatBuffer schema
        configT.startWidth = UInt16(width / 64)
        configT.startHeight = UInt16(height / 64)

        // Core generation parameters
        configT.steps = UInt32(steps)
        configT.model = model
        configT.sampler = sampler
        configT.guidanceScale = guidanceScale
        configT.clipSkip = UInt32(clipSkip)
        configT.shift = shift

        // Seed handling - clamp to UInt32 range for flatbuffer compatibility
        if let seed = seed, seed >= 0 {
            // Mask to UInt32 range to handle seeds that exceed UInt32.max
            configT.seed = UInt32(truncatingIfNeeded: seed)
        } else {
            configT.seed = arc4random()
        }

        configT.seedMode = mapSeedModeToEnum(seedMode)

        // Batch parameters
        configT.id = 0
        configT.batchCount = UInt32(batchCount)
        configT.batchSize = UInt32(batchSize)
        configT.strength = strength

        // Guidance parameters
        configT.imageGuidanceScale = imageGuidanceScale
        configT.clipWeight = clipWeight
        configT.guidanceEmbed = guidanceEmbed
        configT.speedUpWithGuidanceEmbed = speedUpWithGuidanceEmbed
        configT.cfgZeroStar = cfgZeroStar
        configT.cfgZeroInitSteps = cfgZeroInitSteps

        // Compression parameters
        configT.compressionArtifacts = self.compressionArtifacts
        configT.compressionArtifactsQuality = self.compressionArtifactsQuality

        // Mask/Inpaint parameters
        configT.maskBlur = maskBlur
        configT.maskBlurOutset = Int32(maskBlurOutset)
        configT.preserveOriginalAfterInpaint = preserveOriginalAfterInpaint

        // Quality parameters
        configT.sharpness = sharpness
        configT.stochasticSamplingGamma = stochasticSamplingGamma
        configT.aestheticScore = aestheticScore
        configT.negativeAestheticScore = negativeAestheticScore

        // Image prior parameters
        configT.negativePromptForImagePrior = negativePromptForImagePrior
        configT.imagePriorSteps = UInt32(imagePriorSteps)

        // Crop/Size parameters
        configT.cropTop = Int32(cropTop)
        configT.cropLeft = Int32(cropLeft)
        configT.originalImageHeight = UInt32(originalImageHeight > 0 ? originalImageHeight : height)
        configT.originalImageWidth = UInt32(originalImageWidth > 0 ? originalImageWidth : width)
        configT.targetImageHeight = UInt32(targetImageHeight > 0 ? targetImageHeight : height)
        configT.targetImageWidth = UInt32(targetImageWidth > 0 ? targetImageWidth : width)
        configT.negativeOriginalImageHeight = UInt32(negativeOriginalImageHeight > 0 ? negativeOriginalImageHeight : height)
        configT.negativeOriginalImageWidth = UInt32(negativeOriginalImageWidth > 0 ? negativeOriginalImageWidth : width)

        // Upscaler parameters
        configT.upscalerScaleFactor = UInt8(upscalerScaleFactor)

        // Text encoder parameters
        configT.resolutionDependentShift = resolutionDependentShift
        configT.t5TextEncoder = t5TextEncoder
        configT.separateClipL = separateClipL
        configT.separateOpenClipG = separateOpenClipG
        configT.separateT5 = separateT5

        // Tiled parameters (FlatBuffer stores tile dimensions in units of 64 pixels)
        configT.tiledDiffusion = tiledDiffusion
        configT.diffusionTileWidth = UInt16(diffusionTileWidth / 64)
        configT.diffusionTileHeight = UInt16(diffusionTileHeight / 64)
        configT.diffusionTileOverlap = UInt16(diffusionTileOverlap / 64)
        configT.tiledDecoding = tiledDecoding
        configT.decodingTileWidth = UInt16(decodingTileWidth / 64)
        configT.decodingTileHeight = UInt16(decodingTileHeight / 64)
        configT.decodingTileOverlap = UInt16(decodingTileOverlap / 64)

        // HiRes Fix parameters
        configT.hiresFix = hiresFix
        configT.hiresFixStartWidth = UInt16(hiresFixWidth / 64)
        configT.hiresFixStartHeight = UInt16(hiresFixHeight / 64)
        configT.hiresFixStrength = hiresFixStrength

        // Upscaler
        configT.upscaler = upscaler?.isEmpty == false ? upscaler : nil

        // Face restoration
        configT.faceRestoration = faceRestoration?.isEmpty == false ? faceRestoration : nil

        // Stage 2 parameters
        configT.stage2Steps = UInt32(stage2Steps)
        configT.stage2Cfg = stage2Guidance
        configT.stage2Shift = stage2Shift

        // TEA Cache parameters
        configT.teaCache = teaCache
        configT.teaCacheStart = Int32(teaCacheStart)
        configT.teaCacheEnd = Int32(teaCacheEnd)
        configT.teaCacheThreshold = teaCacheThreshold
        configT.teaCacheMaxSkipSteps = Int32(teaCacheMaxSkipSteps)

        // Causal inference parameters
        configT.causalInferenceEnabled = causalInferenceEnabled
        configT.causalInference = Int32(causalInference)
        configT.causalInferencePad = Int32(causalInferencePad)

        // Video parameters
        configT.fpsId = UInt32(fps)
        configT.motionBucketId = UInt32(motionScale)
        configT.condAug = guidingFrameNoise
        configT.startFrameCfg = startFrameGuidance
        configT.numFrames = UInt32(numFrames)

        // Refiner parameters
        configT.refinerModel = refinerModel?.isEmpty == false ? refinerModel : nil
        configT.refinerStart = refinerStart
        configT.zeroNegativePrompt = zeroNegativePrompt

        // Configuration name
        configT.name = name

        // Separate text encoder prompts
        configT.clipLText = clipLText
        configT.openClipGText = openClipGText
        configT.t5Text = t5Text

        // Add user-provided controls (ControlNet)
        var controlsArray: [ControlT] = controls.map { control in
            let controlT = ControlT()
            controlT.file = control.file
            controlT.weight = control.weight
            controlT.guidanceStart = control.guidanceStart
            controlT.guidanceEnd = control.guidanceEnd
            controlT.controlMode = control.controlMode
            controlT.noPrompt = false
            controlT.globalAveragePooling = false
            controlT.downSamplingRate = 1.0
            controlT.targetBlocks = []
            DrawThingsClientLogger.debug("Added ControlNet control: \(control.file)")
            return controlT
        }

        // Add inpaint control if enabled
        if enableInpainting {
            let inpaintControl = ControlT()
            inpaintControl.inputOverride = .inpaint
            inpaintControl.weight = 1.0
            inpaintControl.guidanceStart = 0.0
            inpaintControl.guidanceEnd = 1.0
            inpaintControl.noPrompt = false
            inpaintControl.globalAveragePooling = true
            inpaintControl.downSamplingRate = 1.0
            inpaintControl.controlMode = .balanced
            inpaintControl.targetBlocks = []
            inpaintControl.file = ""  // Empty file - mask is sent separately
            controlsArray.append(inpaintControl)
            DrawThingsClientLogger.debug("Added inpaint control to configuration")
        }

        configT.controls = controlsArray

        // Add LoRAs
        configT.loras = loras.map { lora in
            let loraT = LoRAT()
            loraT.file = lora.file
            loraT.weight = lora.weight
            loraT.mode = lora.mode
            return loraT
        }

        // Pack into FlatBuffer
        var builder = FlatBufferBuilder(initialSize: 1024)
        var mutableConfigT = configT
        let offset = GenerationConfiguration.pack(&builder, obj: &mutableConfigT)
        builder.finish(offset: offset)

        // Return as Data
        let bufferPointer = builder.sizedByteArray
        return Data(bufferPointer)
    }

    // Map seed mode to FlatBuffer enum. The raw values line up 1:1
    // (legacy=0, torchcpucompatible=1, scalealike=2, nvidiagpucompatible=3),
    // so preserve the pasted value exactly; only fall back for unknown modes.
    private func mapSeedModeToEnum(_ mode: Int32) -> SeedMode {
        SeedMode(rawValue: Int8(truncatingIfNeeded: mode)) ?? .torchcpucompatible
    }
}
