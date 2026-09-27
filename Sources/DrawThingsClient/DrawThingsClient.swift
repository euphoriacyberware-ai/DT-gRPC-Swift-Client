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
import Combine
import Foundation

/// Images and audio from ``DrawThingsClient/generateImageAndAudio(prompt:negativePrompt:configuration:image:mask:hints:override:)``.
public struct GenerationOutput {
    public let images: [PlatformImage]
    public let audio: [AVAudioPCMBuffer]
}

/// A main-actor wrapper around ``DrawThingsService`` for SwiftUI.
@MainActor
public class DrawThingsClient: ObservableObject {
    public let service: DrawThingsService

    @Published public var isConnected = false
    /// Progress of the current generation, or nil when idle.
    @Published public var currentProgress: GenerationProgress?
    /// The latest preview of the current generation.
    @Published public var currentPreview: PlatformImage?
    @Published public var lastError: Error?

    public init(address: String, options: ConnectionOptions = .default) throws {
        self.service = try DrawThingsService(address: address, options: options)
    }

    public func connect() async {
        do {
            try await service.echo()
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
        override: MetadataOverride? = nil
    ) async throws -> [PlatformImage] {
        try await generate(prompt: prompt, negativePrompt: negativePrompt, configuration: configuration,
                           image: image, mask: mask, hints: hints, override: override).platformImages
    }

    public func generateImageAndAudio(
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: PlatformImage? = nil,
        mask: PlatformImage? = nil,
        hints: [HintProto] = [],
        override: MetadataOverride? = nil
    ) async throws -> GenerationOutput {
        let result = try await generate(prompt: prompt, negativePrompt: negativePrompt, configuration: configuration,
                                        image: image, mask: mask, hints: hints, override: override)
        return GenerationOutput(images: result.platformImages, audio: try result.audio.map { try $0.pcmBuffer() })
    }

    private func generate(
        prompt: String,
        negativePrompt: String,
        configuration: DrawThingsConfiguration,
        image: PlatformImage?,
        mask: PlatformImage?,
        hints: [HintProto],
        override: MetadataOverride?
    ) async throws -> GenerationResult {
        let request = GenerationRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: try image.map(Self.cgImage),
            mask: try mask.map(Self.cgImage),
            hints: hints,
            override: override
        )
        currentProgress = GenerationProgress(stage: .textEncoding, totalSteps: Int(configuration.steps))
        currentPreview = nil
        defer {
            currentProgress = nil
            currentPreview = nil
        }
        for try await event in service.stream(request) {
            switch event {
            case .progress(let progress):
                currentProgress = progress
            case .preview(let preview):
                currentPreview = PlatformImage.fromCGImage(preview)
            case .completed(let result):
                return result
            default:
                break
            }
        }
        throw CancellationError()
    }

    private static func cgImage(_ image: PlatformImage) throws -> CGImage {
        guard let cgImage = image.cgImageRepresentation else { throw ImageError.invalidImage }
        return cgImage
    }
}
