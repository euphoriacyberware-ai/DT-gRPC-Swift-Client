import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import DrawThingsClient

@Suite("Generation types")
struct GenerationTypeTests {
    @Test func mapsSignpostsToStages() {
        let sampling = ImageGenerationSignpostProto.with { $0.sampling = .with { $0.step = 7 } }
        #expect(GenerationStage(sampling) == .sampling(step: 7))
        let decoded = ImageGenerationSignpostProto.with { $0.imageDecoded = .init() }
        #expect(GenerationStage(decoded) == .imageDecoding)
        #expect(GenerationStage(ImageGenerationSignpostProto()) == nil)
    }

    @Test func progressFractionOnlyDuringFirstPassSampling() {
        #expect(GenerationProgress(stage: .sampling(step: 5), step: 5, totalSteps: 20).fractionCompleted == 0.25)
        #expect(GenerationProgress(stage: .sampling(step: 30), step: 30, totalSteps: 20).fractionCompleted == 1)
        #expect(GenerationProgress(stage: .imageDecoding, totalSteps: 20).fractionCompleted == nil)
        #expect(GenerationProgress(stage: .secondPassSampling(step: 2), step: 2, totalSteps: 20).fractionCompleted == nil)
    }

    @Test func imageModelsAreNeverVideo() {
        // numFrames defaults to 14 for every configuration.
        let media = MediaProfile(configuration: DrawThingsConfiguration(model: "sd_xl_base_1.0_f16.ckpt"))
        #expect(!media.isVideo)
        #expect(media.frameRate == nil)
        #expect(media.audioSampleRate == nil)
    }

    @Test func videoModelsResolveFrameAndSampleRates() {
        let media = MediaProfile(configuration: DrawThingsConfiguration(model: "ltx_2.3_22b_distilled_f16.ckpt", numFrames: 49))
        #expect(media.family == .ltx23)
        #expect(media.isVideo)
        #expect(media.frameRate == 25)
        #expect(media.audioSampleRate == 48_000)

        let single = MediaProfile(configuration: DrawThingsConfiguration(model: "wan_v2.1_14b_t2v_q8p.ckpt", numFrames: 1))
        #expect(!single.isVideo)
    }

    @Test func requestOverridesWin() {
        let request = GenerationRequest(
            prompt: "x",
            configuration: DrawThingsConfiguration(model: "custom_video_model.ckpt", numFrames: 9),
            modelFamily: .minimaxH3,
            audioSampleRate: 44_100
        )
        #expect(request.media.family == .minimaxH3)
        #expect(request.media.isVideo)
        #expect(request.media.audioSampleRate == 44_100)
    }
}

@Suite("GeneratedAudio")
struct GeneratedAudioTests {
    /// A CCV Float32 tensor: 68-byte header then samples.
    private func tensor(dims: [UInt32], format: UInt32, samples: [Float]) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[1] = 1
        header[2] = format
        header[3] = 0x04000
        for (i, d) in dims.enumerated() { header[5 + i] = d }
        var data = header.withUnsafeBufferPointer { Data(buffer: $0) }
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }

    @Test func decodesPlanarStereo() throws {
        // [channels, samples] planar: L L L R R R
        let audio = try GeneratedAudio(tensor: tensor(dims: [2, 3], format: 0x01, samples: [0.1, 0.2, 0.3, -0.1, -0.2, -0.3]), sampleRate: 24_000)
        #expect(audio.channelCount == 2)
        #expect(audio.frameCount == 3)
        #expect(audio.channels[0] == [0.1, 0.2, 0.3])
        #expect(audio.channels[1] == [-0.1, -0.2, -0.3])
    }

    @Test func decodesInterleavedNHWC() throws {
        // [1, H=3, W=1, C=2] interleaved: L R L R L R
        let audio = try GeneratedAudio(tensor: tensor(dims: [1, 3, 1, 2], format: 0x02, samples: [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]), sampleRate: 24_000)
        #expect(audio.channels == [[0.1, 0.2, 0.3], [-0.1, -0.2, -0.3]])
    }

    @Test func rejectsTruncatedOrOverflowingTensors() {
        #expect(throws: (any Error).self) {
            try GeneratedAudio(tensor: tensor(dims: [2, 1000], format: 0x01, samples: [0, 0]), sampleRate: 24_000)
        }
        #expect(throws: (any Error).self) {
            try GeneratedAudio(tensor: tensor(dims: [1, .max, .max, 1], format: 0x02, samples: []), sampleRate: 24_000)
        }
    }

    @Test func wavDataRoundTripsThroughAVAudioFile() throws {
        let samples: [Float] = (0..<480).map { sin(Float($0) * 0.05) * 0.5 }
        let audio = GeneratedAudio(channels: [samples, samples.map { -$0 }], sampleRate: 48_000)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try audio.wavData().write(to: url)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.length == 480)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
        try file.read(into: buffer)
        let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 480)
        let right = UnsafeBufferPointer(start: buffer.floatChannelData![1], count: 480)
        #expect(Array(left) == samples)
        #expect(Array(right) == samples.map { -$0 })
    }

    @Test func pcmBufferMatchesSamples() throws {
        let audio = GeneratedAudio(channels: [[0.25, 0.5]], sampleRate: 16_000)
        let buffer = try audio.pcmBuffer()
        #expect(buffer.frameLength == 2)
        #expect(buffer.format.sampleRate == 16_000)
        #expect(buffer.floatChannelData![0][1] == 0.5)
    }
}

@Suite("Image tensors")
struct ImageTensorTests {
    @Test func rgbTensorRoundTripsToCGImage() throws {
        let width = 8, height = 4
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let source = try #require(context.makeImage())

        let tensor = try ImageHelpers.imageToDTTensor(source, forceRGB: true)
        let decoded = try ImageHelpers.dtTensorToCGImage(tensor)

        #expect(decoded.width == width)
        #expect(decoded.height == height)
        let pixels = try #require(decoded.dataProvider?.data as Data?)
        // Float16 round-trip of 0.5 can land on 127 or 128.
        #expect(pixels[0] == 255)
        #expect((127...128).contains(pixels[1]))
        #expect(pixels[2] == 0)
    }
}
