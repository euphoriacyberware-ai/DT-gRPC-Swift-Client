//
//  DrawThingsClient.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import AVFoundation
import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct GenerationOutput: Sendable {
    public let images: [PlatformImage]
    public let audio: [AVAudioPCMBuffer]
}

@MainActor
public class DrawThingsClient: ObservableObject {
    private let service: DrawThingsService
    
    @Published public var isConnected = false
    @Published public var currentProgress: ImageGenerationProgress?
    @Published public var lastError: Error?
    
    public init(address: String, useTLS: Bool = true) throws {
        self.service = try DrawThingsService(address: address, useTLS: useTLS)
    }
    
    public func connect(sharedSecret: String? = nil) async {
        do {
            _ = try await service.echo(sharedSecret: sharedSecret)
            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            lastError = error
        }
    }
    
    public func generateImage(
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: PlatformImage? = nil,
        mask: PlatformImage? = nil,
        hints: [HintProto] = [],
        sharedSecret: String? = nil
    ) async throws -> [PlatformImage] {
        let resultData = try await callService(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: image,
            mask: mask,
            hints: hints,
            sharedSecret: sharedSecret
        )
        return try resultData.map { try ImageHelpers.dtTensorToImage($0) }
    }

    public func generateImageAndAudio(
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: PlatformImage? = nil,
        mask: PlatformImage? = nil,
        hints: [HintProto] = [],
        sharedSecret: String? = nil
    ) async throws -> GenerationOutput {
        var audioBuffers: [AVAudioPCMBuffer] = []

        let resultData = try await callService(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: image,
            mask: mask,
            hints: hints,
            sharedSecret: sharedSecret,
            audioHandler: { audioData in
                if let buffer = try? AudioHelpers.ccvTensorToAudioBuffer(audioData) {
                    audioBuffers.append(buffer)
                }
            }
        )

        let images = try resultData.map { try ImageHelpers.dtTensorToImage($0) }
        return GenerationOutput(images: images, audio: audioBuffers)
    }

    private func callService(
        prompt: String,
        negativePrompt: String,
        configuration: DrawThingsConfiguration,
        image: PlatformImage?,
        mask: PlatformImage?,
        hints: [HintProto] = [],
        sharedSecret: String? = nil,
        audioHandler: @escaping (Data) async -> Void = { _ in }
    ) async throws -> [Data] {
        currentProgress = ImageGenerationProgress()

        let configData = try configuration.toFlatBufferData()

        var imageData: Data?
        var maskData: Data?

        if let image = image {
            imageData = try ImageHelpers.imageToDTTensor(image, forceRGB: true)
        }

        if let mask = mask {
            // Draw Things' mask format is a 1-byte-per-pixel alpha-derived mask
            // (68-byte header + 0/2 values), not an RGB image tensor. Encoding
            // the mask with imageToDTTensor produces the wrong tensor shape and
            // crashes the DT server in isInpainting() with an out-of-bounds
            // read. createMaskFromAlpha emits the format DT expects.
            maskData = try ImageHelpers.createMaskFromAlpha(mask)
        }

        let result = try await service.generateImage(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configData,
            image: imageData,
            mask: maskData,
            hints: hints,
            sharedSecret: sharedSecret,
            progressHandler: { [weak self] signpost in
                await MainActor.run {
                    self?.updateProgress(signpost)
                }
            },
            audioHandler: audioHandler
        )

        currentProgress = nil
        return result
    }
    
    private func updateProgress(_ signpost: ImageGenerationSignpostProto?) {
        guard let signpost = signpost else { return }
        
        switch signpost.signpost {
        case .textEncoded:
            currentProgress?.stage = .textEncoding
        case .imageEncoded:
            currentProgress?.stage = .imageEncoding
        case .sampling(let sampling):
            currentProgress?.stage = .sampling(step: Int(sampling.step))
        case .imageDecoded:
            currentProgress?.stage = .imageDecoding
        case .secondPassImageEncoded:
            currentProgress?.stage = .secondPassImageEncoding
        case .secondPassSampling(let sampling):
            currentProgress?.stage = .secondPassSampling(step: Int(sampling.step))
        case .secondPassImageDecoded:
            currentProgress?.stage = .secondPassImageDecoding
        case .faceRestored:
            currentProgress?.stage = .faceRestoration
        case .imageUpscaled:
            currentProgress?.stage = .imageUpscaling
        default:
            break
        }
    }
}

public class ImageGenerationProgress: ObservableObject {
    @Published public var stage: GenerationStage = .textEncoding
    
    public init() {}
}

public enum GenerationStage {
    case textEncoding
    case imageEncoding
    case sampling(step: Int)
    case imageDecoding
    case secondPassImageEncoding
    case secondPassSampling(step: Int)
    case secondPassImageDecoding
    case faceRestoration
    case imageUpscaling
    
    public var description: String {
        switch self {
        case .textEncoding:
            return "Encoding text prompt..."
        case .imageEncoding:
            return "Encoding input image..."
        case .sampling(let step):
            return "Generating image (step \(step))..."
        case .imageDecoding:
            return "Decoding generated image..."
        case .secondPassImageEncoding:
            return "Preparing second pass..."
        case .secondPassSampling(let step):
            return "Second pass generation (step \(step))..."
        case .secondPassImageDecoding:
            return "Processing second pass..."
        case .faceRestoration:
            return "Restoring faces..."
        case .imageUpscaling:
            return "Upscaling image..."
        }
    }
}
