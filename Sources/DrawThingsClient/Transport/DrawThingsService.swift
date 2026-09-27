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
import FlatBuffers
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf

/// A connection to a Draw Things gRPC server.
///
/// Create one per server and keep it for the life of the connection; call ``shutdown()``
/// when you are done with it.
public actor DrawThingsService {
    public nonisolated let endpoint: ServerEndpoint
    public nonisolated let options: ConnectionOptions
    /// Resolves the model specifications sent with each request.
    public nonisolated let modelSpecs: ModelSpecStore

    private let grpcClient: GRPCClient<HTTP2ClientTransport.Posix>
    private let client: ImageGenerationService.Client<HTTP2ClientTransport.Posix>
    private let connectionTask: Task<Void, Never>
    /// The server's metadata from its last echo reply.
    private var serverOverride: MetadataOverride?
    private var hasEchoed = false
    private var echoTask: Task<EchoReply, any Error>?

    public init(endpoint: ServerEndpoint, options: ConnectionOptions = .default) throws {
        self.endpoint = endpoint
        self.options = options
        self.modelSpecs = ModelSpecStore(source: options.modelSpecs)

        let target: any ResolvableTarget = endpoint.isIPv6Literal
            ? .ipv6(address: endpoint.host, port: endpoint.port)
            : .dns(host: endpoint.host, port: endpoint.port)
        let transport = try HTTP2ClientTransport.Posix(
            target: target,
            transportSecurity: try Self.transportSecurity(for: options.security, endpoint: endpoint),
            config: .defaults { config in
                // Draw Things compresses large responses.
                config.compression.enabledAlgorithms = .all
            }
        )
        let grpcClient = GRPCClient(transport: transport)
        self.grpcClient = grpcClient
        self.client = ImageGenerationService.Client(wrapping: grpcClient)
        self.connectionTask = Task {
            do {
                try await grpcClient.runConnections()
            } catch {
                DTLogger.error("gRPC connection ended with error: \(error)", category: .connection)
            }
        }
    }

    /// Parses `address` (see ``ServerEndpoint/init(_:)``) and connects with `options`.
    public init(address: String, options: ConnectionOptions = .default) throws {
        try self.init(endpoint: ServerEndpoint(address), options: options)
    }

    deinit {
        // Non-blocking: in-flight calls finish, then the connection task exits.
        grpcClient.beginGracefulShutdown()
    }

    /// Closes the connection once in-flight calls finish.
    public func shutdown() async {
        grpcClient.beginGracefulShutdown()
        await connectionTask.value
    }

    // MARK: - Echo

    /// Checks the connection and returns the server's reply, refreshing the cached server
    /// metadata (the models, LoRAs and control nets the server has installed).
    @discardableResult
    public func echo(name: String = "DrawThingsClient") async throws -> EchoReply {
        let request = EchoRequest.with {
            $0.name = name
            if let secret = options.sharedSecret { $0.sharedSecret = secret }
        }
        do {
            let reply = try await client.echo(request: ClientRequest(message: request), options: unaryCallOptions)
            if reply.sharedSecretMissing {
                throw DrawThingsError.unauthenticated
            }
            if reply.hasOverride {
                serverOverride = reply.override
                await modelSpecs.ingestServerOverride(reply.override)
            }
            hasEchoed = true
            return reply
        } catch {
            throw DrawThingsError.map(error)
        }
    }

    /// Echoes once before the first generation, sharing one call between concurrent callers.
    private func ensureEchoed() async throws {
        guard !hasEchoed else { return }
        if let inFlight = echoTask {
            _ = try await inFlight.value
            return
        }
        let task = Task { try await self.echo() }
        echoTask = task
        defer { echoTask = nil }
        _ = try await task.value
    }

    // MARK: - Files

    /// Asks the server which of the given model files it has installed.
    public func checkFilesExist(files: [String], filesWithHash: [String] = []) async throws -> FileExistenceResponse {
        let request = FileListRequest.with {
            $0.files = files
            $0.filesWithHash = filesWithHash
            if let secret = options.sharedSecret { $0.sharedSecret = secret }
        }
        do {
            return try await client.filesExist(request: ClientRequest(message: request), options: unaryCallOptions)
        } catch {
            throw DrawThingsError.map(error)
        }
    }

    // MARK: - Generation

    /// Generates images (and audio, for video models with sound).
    ///
    /// Handlers are awaited in the order the server sends events, and the call returns only
    /// after every handler has finished. Cancelling the calling task cancels the generation
    /// on the server.
    ///
    /// - Parameters:
    ///   - configuration: FlatBuffer-encoded configuration (``DrawThingsConfiguration/toFlatBufferData()``).
    ///   - image: Input image tensor for image-to-image.
    ///   - mask: Inpainting mask tensor.
    ///   - contents: Additional tensors referenced by SHA-256 from hints.
    ///   - override: Explicit model metadata; when nil, specs are resolved by ``modelSpecs``.
    /// - Returns: The generated image tensors.
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
        progressHandler: @escaping @Sendable (ImageGenerationSignpostProto?) async -> Void = { _ in },
        previewHandler: @escaping @Sendable (Data) async -> Void = { _ in },
        audioHandler: @escaping @Sendable (Data) async -> Void = { _ in }
    ) async throws -> [Data] {
        try await ensureEchoed()

        let effectiveOverride: MetadataOverride?
        if let override {
            effectiveOverride = override
        } else {
            let (modelFile, loraFiles) = try Self.modelAndLoRAFiles(in: configuration)
            if let modelFile {
                effectiveOverride = await modelSpecs.override(forModel: modelFile, loraFiles: loraFiles, base: serverOverride)
            } else {
                effectiveOverride = serverOverride
            }
        }

        let request = makeRequest(
            prompt: prompt, negativePrompt: negativePrompt, configuration: configuration,
            image: image, mask: mask, hints: hints, contents: contents,
            override: effectiveOverride, scaleFactor: scaleFactor
        )
        DTLogger.debug("Sending request: config \(configuration.count) bytes, hints \(hints.count), contents \(request.contents.count)", category: .grpc)

        do {
            return try await client.generateImage(request: ClientRequest(message: request), options: streamingCallOptions) { response in
                var assembler = ResponseAssembler()
                var images: [Data] = []
                var lastPreview: Data?
                var count = 0
                for try await message in response.messages {
                    count += 1
                    if message.hasCurrentSignpost {
                        await progressHandler(message.currentSignpost)
                    }
                    if message.hasPreviewImage {
                        lastPreview = message.previewImage
                        await previewHandler(message.previewImage)
                    }
                    let output = assembler.consume(message)
                    images.append(contentsOf: output.images)
                    for audio in output.audio {
                        await audioHandler(audio)
                    }
                }
                DTLogger.debug("Stream completed after \(count) responses, \(images.count) image(s)", category: .grpc)
                if assembler.hasIncompleteTensor {
                    throw DrawThingsError.incompleteResponse("the stream ended in the middle of a chunked tensor")
                }
                if images.isEmpty, let lastPreview {
                    DTLogger.info("No generated images received, using last preview image as result", category: .grpc)
                    images.append(lastPreview)
                }
                return images
            }
        } catch {
            throw DrawThingsError.map(error)
        }
    }

    // MARK: - Helpers

    /// Options for generation: no timeout, and message limits large enough for full-size
    /// tensors in both directions. The NIO transport enforces `maxRequestMessageBytes` on every
    /// message its stream handler decodes, including responses, so both limits are raised.
    private var streamingCallOptions: CallOptions {
        var callOptions = CallOptions.defaults
        callOptions.maxRequestMessageBytes = options.maxMessageBytes
        callOptions.maxResponseMessageBytes = options.maxMessageBytes
        return callOptions
    }

    private var unaryCallOptions: CallOptions {
        var callOptions = streamingCallOptions
        callOptions.timeout = options.requestTimeout
        return callOptions
    }

    private func makeRequest(
        prompt: String, negativePrompt: String, configuration: Data,
        image: Data?, mask: Data?, hints: [HintProto], contents: [Data],
        override: MetadataOverride?, scaleFactor: Int32
    ) -> ImageGenerationRequest {
        ImageGenerationRequest.with {
            $0.scaleFactor = scaleFactor
            $0.user = options.clientIdentity.user
            $0.device = options.clientIdentity.device
            $0.prompt = prompt
            $0.negativePrompt = negativePrompt
            $0.configuration = configuration
            $0.hints = hints
            $0.chunked = true
            if let secret = options.sharedSecret { $0.sharedSecret = secret }
            if let override { $0.override = override }

            // Content-addressed storage: `image` / `mask` hold the SHA-256 of a tensor
            // whose bytes are sent once in `contents`.
            var seen = Set<Data>()
            var uniqueContents = [Data]()
            func store(_ tensor: Data) -> Data {
                let hash = Data(SHA256.hash(data: tensor))
                if seen.insert(hash).inserted { uniqueContents.append(tensor) }
                return hash
            }
            for tensor in contents { _ = store(tensor) }
            if let image { $0.image = store(image) }
            if let mask { $0.mask = store(mask) }
            $0.contents = uniqueContents
        }
    }

    /// Reads the model and LoRA file names from a FlatBuffer configuration.
    static func modelAndLoRAFiles(in configuration: Data) throws -> (model: String?, loras: [String]) {
        var buffer = ByteBuffer(data: configuration)
        let config: GenerationConfiguration
        do {
            config = try getCheckedRoot(byteBuffer: &buffer)
        } catch {
            throw DrawThingsError.invalidConfiguration(field: "configuration", reason: "not a valid FlatBuffer (\(error))")
        }
        let loras = (0..<config.lorasCount).compactMap { config.loras(at: $0)?.file }
        return (config.model, loras)
    }

    private static func transportSecurity(
        for security: TransportSecurity,
        endpoint: ServerEndpoint
    ) throws -> HTTP2ClientTransport.Posix.TransportSecurity {
        switch security {
        case .plaintext:
            return .plaintext
        case .tls(let verification):
            return .tls { config in
                switch verification {
                case .automatic:
                    config.serverCertificateVerification = endpoint.isLocalNetwork ? .noVerification : .fullVerification
                case .full:
                    config.serverCertificateVerification = .fullVerification
                case .none:
                    config.serverCertificateVerification = .noVerification
                case .trustRoots(let certificates):
                    // Self-signed certificates rarely match the host name the client dials.
                    config.serverCertificateVerification = .noHostnameVerification
                    config.trustRoots = .certificates(certificates.map { .bytes(Array($0), format: .pem) })
                }
            }
        }
    }
}
