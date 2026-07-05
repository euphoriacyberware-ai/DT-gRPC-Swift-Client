//
//  DrawThingsService.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import CryptoKit
import Foundation
import GRPC
import NIO
import NIOSSL
import SwiftProtobuf

public actor DrawThingsService {
    private let client: ImageGenerationServiceClient
    private let group: EventLoopGroup
    private let channel: GRPCChannel
    private var models: MetadataOverride?

    public init(address: String, useTLS: Bool = true) throws {
        let components = address.components(separatedBy: ":")
        let host = components.first ?? "localhost"
        let port = Int(components.last ?? "7859") ?? 7859

        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // Configure channel to accept large messages (for full-resolution images)
        if useTLS {
            // For localhost/development, create TLS config that doesn't verify certificates
            let tlsConfig = try GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
                certificateVerification: .none
            )

            self.channel = try GRPCChannelPool.with(
                target: .host(host, port: port),
                transportSecurity: .tls(tlsConfig),
                eventLoopGroup: group
            ) { configuration in
                configuration.maximumReceiveMessageLength = .max
            }
        } else {
            self.channel = try GRPCChannelPool.with(
                target: .host(host, port: port),
                transportSecurity: .plaintext,
                eventLoopGroup: group
            ) { configuration in
                configuration.maximumReceiveMessageLength = .max
            }
        }

        self.client = ImageGenerationServiceClient(channel: channel)
    }
    
    deinit {
        try? channel.close().wait()
        try? group.syncShutdownGracefully()
    }
    
    public func echo(name: String = "Swift-Client", sharedSecret: String? = nil) async throws -> EchoReply {
        let request = EchoRequest.with {
            $0.name = name
            if let sharedSecret = sharedSecret {
                $0.sharedSecret = sharedSecret
            }
        }

        // Configure call options to accept compressed responses
        var callOptions = CallOptions()
        callOptions.messageEncoding = .enabled(.init(
            forRequests: nil,  // Don't compress requests
            decompressionLimit: .absolute(.max)  // Accept compressed responses
        ))

        let call = client.echo(request, callOptions: callOptions)
        let response = try await call.response.get()

        // Cache the models metadata for future requests
        if response.hasOverride {
            self.models = response.override
        }

        return response
    }
    
    public func generateImage(
        prompt: String,
        negativePrompt: String = "",
        configuration: Data,
        image: Data? = nil,
        mask: Data? = nil,
        hints: [HintProto] = [],
        contents: [Data] = [],
        override: MetadataOverride? = nil,
        scaleFactor: Int32 = 1,
        sharedSecret: String? = nil,
        progressHandler: @escaping (ImageGenerationSignpostProto?) async -> Void = { _ in },
        previewHandler: @escaping (Data) async -> Void = { _ in },
        audioHandler: @escaping (Data) async -> Void = { _ in }
    ) async throws -> [Data] {
        
        // Ensure we have models metadata
        if self.models == nil {
            _ = try await echo(sharedSecret: sharedSecret)
        }
        
        let request = ImageGenerationRequest.with {
            $0.scaleFactor = scaleFactor
            $0.user = ProcessInfo.processInfo.hostName
            $0.device = .laptop
            $0.prompt = prompt
            $0.negativePrompt = negativePrompt
            $0.configuration = configuration

            DrawThingsClientLogger.debug("Sending request: prompt='\(prompt)', config size=\(configuration.count) bytes")

            // The ImageGenerationRequest uses content-addressable storage:
            // - `image` / `mask` fields hold the SHA256 hash of the tensor data
            // - `contents` holds the actual raw tensor bytes, indexed by their SHA256 hash
            var casContents = contents

            if let image = image {
                let hashData = Data(SHA256.hash(data: image))
                $0.image = hashData
                casContents.append(image)
                DrawThingsClientLogger.debug("   Image data: \(image.count) bytes (sha256 referenced)")
            }

            if let mask = mask {
                let hashData = Data(SHA256.hash(data: mask))
                $0.mask = hashData
                casContents.append(mask)
                DrawThingsClientLogger.debug("   Mask data: \(mask.count) bytes (sha256 referenced)")
            }

            $0.hints = hints
            if !hints.isEmpty {
                DrawThingsClientLogger.debug("   Hints: \(hints.count) hint(s)")
                for (index, hint) in hints.enumerated() {
                    DrawThingsClientLogger.debug("      Hint \(index): type='\(hint.hintType)', tensors=\(hint.tensors.count)")
                    for (tIndex, tensor) in hint.tensors.enumerated() {
                        DrawThingsClientLogger.debug("         Tensor \(tIndex): size=\(tensor.tensor.count) bytes, weight=\(tensor.weight)")
                    }
                }
            }
            // Deduplicate contents by SHA256 hash
            var seenHashes = Set<Data>()
            $0.contents = casContents.filter { entry in
                let hash = Data(SHA256.hash(data: entry))
                return seenHashes.insert(hash).inserted
            }
            
            if let override = override {
                $0.override = override
            } else if let cachedModels = self.models {
                $0.override = cachedModels
            }

            if let sharedSecret = sharedSecret {
                $0.sharedSecret = sharedSecret
            }

            $0.chunked = true
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var generatedImages: [Data] = []
            var lastImageChunk = Data()
            var lastAudioChunk = Data()
            var lastPreviewImage: Data?
            var expectedDownloadSize: Int64?
            var hasResumed = false
            var responseCount = 0

            // Configure call options to accept compressed responses
            var callOptions = CallOptions()
            callOptions.messageEncoding = .enabled(.init(
                forRequests: nil,
                decompressionLimit: .absolute(.max)
            ))

            let call = client.generateImage(request, callOptions: callOptions) { response in
                responseCount += 1
                DrawThingsClientLogger.debug("Response #\(responseCount) received:")
                DrawThingsClientLogger.debug("   - generatedImages.count: \(response.generatedImages.count)")
                DrawThingsClientLogger.debug("   - generatedAudio.count: \(response.generatedAudio.count)")
                DrawThingsClientLogger.debug("   - chunkState: \(response.chunkState)")
                DrawThingsClientLogger.debug("   - hasCurrentSignpost: \(response.hasCurrentSignpost)")
                DrawThingsClientLogger.debug("   - hasDownloadSize: \(response.hasDownloadSize)")
                DrawThingsClientLogger.debug("   - hasPreviewImage: \(response.hasPreviewImage)")
                DrawThingsClientLogger.debug("   - hasScaleFactor: \(response.hasScaleFactor)")
                DrawThingsClientLogger.debug("   - tags.count: \(response.tags.count)")
                DrawThingsClientLogger.debug("   - signposts.count: \(response.signposts.count)")

                if response.hasDownloadSize {
                    DrawThingsClientLogger.debug("   - downloadSize: \(response.downloadSize)")
                }

                if response.hasScaleFactor {
                    DrawThingsClientLogger.debug("   - scaleFactor: \(response.scaleFactor)")
                }

                if !response.tags.isEmpty {
                    DrawThingsClientLogger.debug("   - tags: \(response.tags)")
                }

                if !response.signposts.isEmpty {
                    DrawThingsClientLogger.debug("   - signposts details:")
                    for (idx, signpost) in response.signposts.enumerated() {
                        DrawThingsClientLogger.debug("     [\(idx)]: \(signpost)")
                    }
                }

                // Handle progress updates
                if response.hasCurrentSignpost {
                    Task {
                        await progressHandler(response.currentSignpost)
                    }
                }

                // Track expected download size
                if response.hasDownloadSize && response.downloadSize > 0 {
                    expectedDownloadSize = response.downloadSize
                    DrawThingsClientLogger.debug("Server indicated download size: \(response.downloadSize) bytes")
                }

                // Capture preview image (the last one will be the final result)
                if response.hasPreviewImage {
                    DrawThingsClientLogger.debug("Preview image received: \(response.previewImage.count) bytes")
                    lastPreviewImage = response.previewImage

                    // Send preview to handler
                    Task {
                        await previewHandler(response.previewImage)
                    }
                }

                // Collect generated images with chunk reassembly
                if !response.generatedImages.isEmpty {
                    var images = response.generatedImages
                    if response.chunkState == .lastChunk {
                        if !lastImageChunk.isEmpty {
                            images[0] = lastImageChunk + images[0]
                            lastImageChunk = Data()
                        }
                        DrawThingsClientLogger.debug("Received \(images.count) image(s) (final chunk):")
                        for (idx, img) in images.enumerated() {
                            DrawThingsClientLogger.debug("   - Image \(idx): \(img.count) bytes")
                        }
                        generatedImages.append(contentsOf: images)
                    } else {
                        // More chunks coming — accumulate
                        for img in images {
                            lastImageChunk.append(img)
                        }
                        DrawThingsClientLogger.debug("Accumulated image chunk: \(lastImageChunk.count) bytes so far")
                    }
                }

                // Deliver generated audio with chunk reassembly via callback
                if !response.generatedAudio.isEmpty {
                    var audio = response.generatedAudio
                    if response.chunkState == .lastChunk {
                        if !lastAudioChunk.isEmpty {
                            audio[0] = lastAudioChunk + audio[0]
                            lastAudioChunk = Data()
                        }
                        DrawThingsClientLogger.debug("Received \(audio.count) audio tensor(s) (final chunk)")
                        for audioData in audio {
                            Task {
                                await audioHandler(audioData)
                            }
                        }
                    } else {
                        for a in audio {
                            lastAudioChunk.append(a)
                        }
                        DrawThingsClientLogger.debug("Accumulated audio chunk: \(lastAudioChunk.count) bytes so far")
                    }
                }
            }

            call.status.whenComplete { result in
                guard !hasResumed else {
                    DrawThingsClientLogger.notice("Attempted to resume continuation twice")
                    return
                }
                hasResumed = true

                DrawThingsClientLogger.debug("Stream completed after \(responseCount) responses")
                switch result {
                case .success:
                    DrawThingsClientLogger.debug("gRPC call completed successfully")

                    // If no images were received directly but we have a preview image, use it
                    if generatedImages.isEmpty && lastPreviewImage != nil {
                        DrawThingsClientLogger.info("No generatedImages received, using last preview image as result")
                        generatedImages.append(lastPreviewImage!)
                    }

                    DrawThingsClientLogger.debug("Total images to return: \(generatedImages.count)")
                    if generatedImages.isEmpty && expectedDownloadSize != nil {
                        DrawThingsClientLogger.notice("Warning: Server indicated \(expectedDownloadSize!) bytes but no images received")
                        DrawThingsClientLogger.info("The server may require a separate request to fetch the image data")
                    }
                    continuation.resume(returning: generatedImages)
                case .failure(let err):
                    DrawThingsClientLogger.error("gRPC call failed: \(err)")
                    continuation.resume(throwing: err)
                }
            }
        }
    }
    
    public func checkFilesExist(files: [String], filesWithHash: [String] = []) async throws -> FileExistenceResponse {
        let request = FileListRequest.with {
            $0.files = files
            $0.filesWithHash = filesWithHash
        }

        let call = client.filesExist(request)
        return try await call.response.get()
    }
}