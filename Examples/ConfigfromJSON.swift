//
//  Config from JSON.swift
//  DrawThingsClient
//  These functions are for creating a DrawThingsConfiguration from JSON provided in a String
//
//  Example Draw Things JSON export:
//  {
//    "aestheticScore": 6,
//    "batchCount": 10,
//    "batchSize": 1,
//    "causalInference": 0,
//    "causalInferencePad": 0,
//    "cfgZeroInitSteps": 0,
//    "cfgZeroStar": false,
//    "clipLText": null,
//    "clipSkip": 1,
//    "clipWeight": 1,
//    "compressionArtifacts": "disabled",
//    "compressionArtifactsQuality": 43.1,
//    "controls": [],
//    "cropLeft": 0,
//    "cropTop": 0,
//    "decodingTileHeight": 640,
//    "decodingTileOverlap": 128,
//    "decodingTileWidth": 640,
//    "diffusionTileHeight": 1024,
//    "diffusionTileOverlap": 128,
//    "diffusionTileWidth": 1024,
//    "faceRestoration": null,
//    "fps": 5,
//    "guidanceEmbed": 3.5,
//    "guidanceScale": 1,
//    "guidingFrameNoise": 0.02,
//    "height": 1280,
//    "hiresFix": false,
//    "hiresFixHeight": 1024,
//    "hiresFixStrength": 0.7,
//    "hiresFixWidth": 1024,
//    "id": 0,
//    "imageGuidanceScale": 1.5,
//    "imagePriorSteps": 5,
//    "loras": [
//      {
//        "file": "zit_natalie_illustrated_lora_f16.ckpt",
//        "mode": "all",
//        "weight": 0.65
//      }
//    ],
//    "maskBlur": 1.5,
//    "maskBlurOutset": 0,
//    "model": "z_image_turbo_1.0_q8p.ckpt",
//    "motionScale": 127,
//    "negativeAestheticScore": 2.5,
//    "negativeOriginalImageHeight": 640,
//    "negativeOriginalImageWidth": 640,
//    "negativePromptForImagePrior": true,
//    "numFrames": 14,
//    "openClipGText": null,
//    "originalImageHeight": 1280,
//    "originalImageWidth": 1280,
//    "preserveOriginalAfterInpaint": true,
//    "refinerModel": null,
//    "refinerStart": 0.85,
//    "resolutionDependentShift": false,
//    "sampler": 17,
//    "seed": 945446116,
//    "seedMode": 2,
//    "separateClipL": false,
//    "separateOpenClipG": false,
//    "separateT5": false,
//    "sharpness": 0,
//    "shift": 3,
//    "speedUpWithGuidanceEmbed": true,
//    "stage2Guidance": 1,
//    "stage2Shift": 1,
//    "stage2Steps": 10,
//    "startFrameGuidance": 1,
//    "steps": 8,
//    "stochasticSamplingGamma": 0.3,
//    "strength": 1,
//    "t5TextEncoder": true,
//    "targetImageHeight": 1280,
//    "targetImageWidth": 1280,
//    "teaCache": false,
//    "teaCacheEnd": -1,
//    "teaCacheMaxSkipSteps": 3,
//    "teaCacheStart": 5,
//    "teaCacheThreshold": 0.2,
//    "tiledDecoding": false,
//    "tiledDiffusion": false,
//    "upscaler": null,
//    "upscalerScaleFactor": 0,
//    "width": 1280,
//    "zeroNegativePrompt": false
//  }

import DrawThingsClient

/// Load configuration from a Draw Things JSON export string.
/// All values not present in the JSON use DrawThingsConfiguration defaults.
func configurationFromJSON(_ jsonString: String) -> DrawThingsConfiguration? {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("Failed to parse JSON")
        return nil
    }

    // Model is required
    guard let model = json["model"] as? String, !model.isEmpty else {
        print("Model name is missing or empty in configuration")
        return nil
    }

    let steps = json["steps"] as? Int ?? 20
    let width = json["width"] as? Int ?? 1024
    let height = json["height"] as? Int ?? 1024

    // Sampler - integer in JSON
    let samplerType: SamplerType
    if let samplerInt = json["sampler"] as? Int,
       let sampler = SamplerType(rawValue: Int8(samplerInt)) {
        samplerType = sampler
    } else {
        samplerType = .dpmpp2mkarras
    }

    let guidanceScale = Float(json["guidanceScale"] as? Double ?? 7.0)

    // Seed - nil means random
    let seed: Int64?
    if let seedValue = json["seed"] as? Int {
        seed = Int64(seedValue)
    } else {
        seed = nil
    }

    // Parse LoRAs - DT exports mode as a string ("all", "base", "refiner")
    var loras: [LoRAConfig] = []
    if let lorasArray = json["loras"] as? [[String: Any]] {
        for loraDict in lorasArray {
            if let file = loraDict["file"] as? String {
                let weight = Float(loraDict["weight"] as? Double ?? 1.0)
                let mode: LoRAMode
                if let modeStr = loraDict["mode"] as? String {
                    mode = mapLoRAModeStringToEnum(modeStr)
                } else if let modeInt = loraDict["mode"] as? Int {
                    mode = LoRAMode(rawValue: Int8(modeInt)) ?? .all
                } else {
                    mode = .all
                }
                loras.append(LoRAConfig(file: file, weight: weight, mode: mode))
            }
        }
    }

    // Parse Controls - DT exports controlImportance as a string ("balanced", "prompt", "control")
    var controls: [ControlConfig] = []
    if let controlsArray = json["controls"] as? [[String: Any]] {
        for controlDict in controlsArray {
            if let file = controlDict["file"] as? String {
                let weight = Float(controlDict["weight"] as? Double ?? 1.0)
                let guidanceStart = Float(controlDict["guidanceStart"] as? Double ?? 0.0)
                let guidanceEnd = Float(controlDict["guidanceEnd"] as? Double ?? 1.0)
                let controlMode: ControlMode
                if let importanceStr = controlDict["controlImportance"] as? String {
                    controlMode = mapControlModeStringToEnum(importanceStr)
                } else if let modeInt = controlDict["controlImportance"] as? Int {
                    controlMode = ControlMode(rawValue: Int8(modeInt)) ?? .balanced
                } else {
                    controlMode = .balanced
                }
                controls.append(ControlConfig(
                    file: file,
                    weight: weight,
                    guidanceStart: guidanceStart,
                    guidanceEnd: guidanceEnd,
                    controlMode: controlMode
                ))
            }
        }
    }

    // Compression artifacts - DT exports as string ("disabled", "jpeg", "webp")
    let compressionArtifacts: CompressionMethod
    if let compStr = json["compressionArtifacts"] as? String {
        compressionArtifacts = mapCompressionMethodStringToEnum(compStr)
    } else if let compInt = json["compressionArtifacts"] as? Int {
        compressionArtifacts = CompressionMethod(rawValue: Int8(compInt)) ?? .disabled
    } else {
        compressionArtifacts = .disabled
    }

    // Optional string fields - treat empty strings as nil
    let refinerModel: String? = {
        guard let s = json["refinerModel"] as? String, !s.isEmpty else { return nil }
        return s
    }()
    let upscaler: String? = {
        guard let s = json["upscaler"] as? String, !s.isEmpty else { return nil }
        return s
    }()
    let faceRestoration: String? = {
        guard let s = json["faceRestoration"] as? String, !s.isEmpty else { return nil }
        return s
    }()

    // Separate text encoder prompts
    let clipLText = json["clipLText"] as? String
    let openClipGText = json["openClipGText"] as? String

    let config = DrawThingsConfiguration(
        width: Int32(width),
        height: Int32(height),
        steps: Int32(steps),
        model: model,
        sampler: samplerType,
        guidanceScale: guidanceScale,
        seed: seed,
        clipSkip: Int32(json["clipSkip"] as? Int ?? 1),
        loras: loras,
        controls: controls,
        shift: Float(json["shift"] as? Double ?? 1.0),
        batchCount: Int32(json["batchCount"] as? Int ?? 1),
        batchSize: Int32(json["batchSize"] as? Int ?? 1),
        strength: Float(json["strength"] as? Double ?? 1.0),
        imageGuidanceScale: Float(json["imageGuidanceScale"] as? Double ?? 1.5),
        clipWeight: Float(json["clipWeight"] as? Double ?? 1.0),
        guidanceEmbed: Float(json["guidanceEmbed"] as? Double ?? 3.5),
        speedUpWithGuidanceEmbed: json["speedUpWithGuidanceEmbed"] as? Bool ?? true,
        cfgZeroStar: json["cfgZeroStar"] as? Bool ?? false,
        cfgZeroInitSteps: Int32(json["cfgZeroInitSteps"] as? Int ?? 0),
        compressionArtifacts: compressionArtifacts,
        compressionArtifactsQuality: Float(json["compressionArtifactsQuality"] as? Double ?? 43.1),
        maskBlur: Float(json["maskBlur"] as? Double ?? 1.5),
        maskBlurOutset: Int32(json["maskBlurOutset"] as? Int ?? 0),
        preserveOriginalAfterInpaint: json["preserveOriginalAfterInpaint"] as? Bool ?? true,
        sharpness: Float(json["sharpness"] as? Double ?? 0.0),
        stochasticSamplingGamma: Float(json["stochasticSamplingGamma"] as? Double ?? 0.3),
        aestheticScore: Float(json["aestheticScore"] as? Double ?? 6.0),
        negativeAestheticScore: Float(json["negativeAestheticScore"] as? Double ?? 2.5),
        negativePromptForImagePrior: json["negativePromptForImagePrior"] as? Bool ?? true,
        imagePriorSteps: Int32(json["imagePriorSteps"] as? Int ?? 5),
        cropTop: Int32(json["cropTop"] as? Int ?? 0),
        cropLeft: Int32(json["cropLeft"] as? Int ?? 0),
        originalImageHeight: Int32(json["originalImageHeight"] as? Int ?? 0),
        originalImageWidth: Int32(json["originalImageWidth"] as? Int ?? 0),
        targetImageHeight: Int32(json["targetImageHeight"] as? Int ?? 0),
        targetImageWidth: Int32(json["targetImageWidth"] as? Int ?? 0),
        negativeOriginalImageHeight: Int32(json["negativeOriginalImageHeight"] as? Int ?? 0),
        negativeOriginalImageWidth: Int32(json["negativeOriginalImageWidth"] as? Int ?? 0),
        upscalerScaleFactor: Int32(json["upscalerScaleFactor"] as? Int ?? 0),
        resolutionDependentShift: json["resolutionDependentShift"] as? Bool ?? false,
        t5TextEncoder: json["t5TextEncoder"] as? Bool ?? true,
        separateClipL: json["separateClipL"] as? Bool ?? false,
        separateOpenClipG: json["separateOpenClipG"] as? Bool ?? false,
        separateT5: json["separateT5"] as? Bool ?? false,
        tiledDiffusion: json["tiledDiffusion"] as? Bool ?? false,
        diffusionTileWidth: Int32(json["diffusionTileWidth"] as? Int ?? 1024),
        diffusionTileHeight: Int32(json["diffusionTileHeight"] as? Int ?? 1024),
        diffusionTileOverlap: Int32(json["diffusionTileOverlap"] as? Int ?? 128),
        tiledDecoding: json["tiledDecoding"] as? Bool ?? false,
        decodingTileWidth: Int32(json["decodingTileWidth"] as? Int ?? 640),
        decodingTileHeight: Int32(json["decodingTileHeight"] as? Int ?? 640),
        decodingTileOverlap: Int32(json["decodingTileOverlap"] as? Int ?? 128),
        hiresFix: json["hiresFix"] as? Bool ?? false,
        hiresFixWidth: Int32(json["hiresFixWidth"] as? Int ?? 1024),
        hiresFixHeight: Int32(json["hiresFixHeight"] as? Int ?? 1024),
        hiresFixStrength: Float(json["hiresFixStrength"] as? Double ?? 0.7),
        stage2Steps: Int32(json["stage2Steps"] as? Int ?? 10),
        stage2Guidance: Float(json["stage2Guidance"] as? Double ?? 1.0),
        stage2Shift: Float(json["stage2Shift"] as? Double ?? 1.0),
        teaCache: json["teaCache"] as? Bool ?? false,
        teaCacheStart: Int32(json["teaCacheStart"] as? Int ?? 5),
        teaCacheEnd: Int32(json["teaCacheEnd"] as? Int ?? -1),
        teaCacheThreshold: Float(json["teaCacheThreshold"] as? Double ?? 0.2),
        teaCacheMaxSkipSteps: Int32(json["teaCacheMaxSkipSteps"] as? Int ?? 3),
        causalInferenceEnabled: json["causalInferenceEnabled"] as? Bool ?? false,
        causalInference: Int32(json["causalInference"] as? Int ?? 0),
        causalInferencePad: Int32(json["causalInferencePad"] as? Int ?? 0),
        fps: Int32(json["fps"] as? Int ?? 5),
        motionScale: Int32(json["motionScale"] as? Int ?? 127),
        guidingFrameNoise: Float(json["guidingFrameNoise"] as? Double ?? 0.02),
        startFrameGuidance: Float(json["startFrameGuidance"] as? Double ?? 1.0),
        numFrames: Int32(json["numFrames"] as? Int ?? 14),
        refinerModel: refinerModel,
        refinerStart: Float(json["refinerStart"] as? Double ?? 0.85),
        zeroNegativePrompt: json["zeroNegativePrompt"] as? Bool ?? false,
        upscaler: upscaler,
        faceRestoration: faceRestoration,
        clipLText: clipLText,
        openClipGText: openClipGText,
        seedMode: Int32(json["seedMode"] as? Int ?? 2)
    )

    return config
}

// MARK: - Enum Mapping Helpers

/// Map LoRA mode string from Draw Things JSON to LoRAMode enum
private func mapLoRAModeStringToEnum(_ mode: String) -> LoRAMode {
    switch mode.lowercased() {
    case "all": return .all
    case "base": return .base
    case "refiner": return .refiner
    default: return .all
    }
}

/// Map control importance string from Draw Things JSON to ControlMode enum
private func mapControlModeStringToEnum(_ importance: String) -> ControlMode {
    switch importance.lowercased() {
    case "balanced": return .balanced
    case "prompt": return .prompt
    case "control": return .control
    default: return .balanced
    }
}

/// Map compression artifacts string from Draw Things JSON to CompressionMethod enum
private func mapCompressionMethodStringToEnum(_ method: String) -> CompressionMethod {
    switch method.lowercased() {
    case "disabled": return .disabled
    case "h264": return .h264
    case "h265": return .h265
    case "jpeg": return .jpeg
    default: return .disabled
    }
}
