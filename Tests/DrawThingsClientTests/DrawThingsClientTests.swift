import XCTest
import FlatBuffers
@testable import DrawThingsClient

final class DrawThingsClientTests: XCTestCase {

    func testCGImageTensorEncoderMatchesPlatformImageWrapper() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let cgImage = try XCTUnwrap(context.makeImage())
#if os(macOS)
        let platformImage = NSImage(cgImage: cgImage, size: NSSize(width: 3, height: 2))
#else
        let platformImage = UIImage(cgImage: cgImage)
#endif

        XCTAssertEqual(
            try ImageHelpers.imageToDTTensor(cgImage, forceRGB: false),
            try ImageHelpers.imageToDTTensor(platformImage, forceRGB: false)
        )
        XCTAssertEqual(
            try ImageHelpers.imageToDTTensor(cgImage, forceRGB: true),
            try ImageHelpers.imageToDTTensor(platformImage, forceRGB: true)
        )
    }

    /// The seed mode must survive `toFlatBufferData()` unchanged — regression for a
    /// bug that collapsed scalealike(2) and nvidiagpucompatible(3) to
    /// torchcpucompatible, which changes the initial noise and breaks reproduction.
    func testSeedModeSurvivesEncoding() throws {
        let cases: [(Int32, SeedMode)] = [
            (0, .legacy),
            (1, .torchcpucompatible),
            (2, .scalealike),
            (3, .nvidiagpucompatible),
        ]
        for (mode, expected) in cases {
            let config = DrawThingsConfiguration(
                width: 512, height: 512, steps: 20,
                model: "sd_xl_base_1.0.safetensors", guidanceScale: 7.0,
                seedMode: mode
            )
            let data = try config.toFlatBufferData()
            var buffer = ByteBuffer(data: data)
            let rootOffset = Int32(buffer.read(def: UInt32.self, position: 0))
            let root = GenerationConfiguration(buffer, o: rootOffset)
            XCTAssertEqual(root.seedMode, expected, "seedMode \(mode) should encode as \(expected)")
        }
    }

    /// Regression: FlatBuffers omits any scalar equal to its schema default, and
    /// the Draw Things schema defaults these to true / non-zero. Without
    /// `serializeDefaults: true` the encoder silently dropped them, the server
    /// read back its own default, and generation diverged from the app for an
    /// identical config + seed.
    func testSchemaDefaultValuedFieldsSurviveEncoding() throws {
        let config = DrawThingsConfiguration(
            width: 1024, height: 1024, steps: 8,
            model: "z_image_turbo_1.0_q8p.ckpt", guidanceScale: 1.0,
            shift: 3.0,
            imageGuidanceScale: 0.0,
            clipWeight: 0.0,
            guidanceEmbed: 0.0,
            speedUpWithGuidanceEmbed: false,
            preserveOriginalAfterInpaint: false,
            stochasticSamplingGamma: 0.0,
            negativePromptForImagePrior: false,
            resolutionDependentShift: false,
            t5TextEncoder: false,
            teaCacheEnd: 0,
            causalInference: 0
        )
        let data = try config.toFlatBufferData()
        var buffer = ByteBuffer(data: data)
        let rootOffset = Int32(buffer.read(def: UInt32.self, position: 0))
        let root = GenerationConfiguration(buffer, o: rootOffset)

        XCTAssertFalse(root.resolutionDependentShift)
        XCTAssertFalse(root.t5TextEncoder)
        XCTAssertFalse(root.speedUpWithGuidanceEmbed)
        XCTAssertFalse(root.preserveOriginalAfterInpaint)
        XCTAssertFalse(root.negativePromptForImagePrior)
        XCTAssertEqual(root.imageGuidanceScale, 0.0)
        XCTAssertEqual(root.clipWeight, 0.0)
        XCTAssertEqual(root.guidanceEmbed, 0.0)
        XCTAssertEqual(root.stochasticSamplingGamma, 0.0)
        XCTAssertEqual(root.teaCacheEnd, 0)
        XCTAssertEqual(root.causalInference, 0)
        XCTAssertEqual(root.shift, 3.0)
    }

    /// The app sends 0 for unset SDXL micro-conditioning sizes; we must not
    /// substitute the start size, or our request differs from the UI's.
    func testUnsetConditioningSizesArePassedThroughAsZero() throws {
        let config = DrawThingsConfiguration(
            width: 1024, height: 1024, steps: 8,
            model: "z_image_turbo_1.0_q8p.ckpt", guidanceScale: 1.0
        )
        let data = try config.toFlatBufferData()
        var buffer = ByteBuffer(data: data)
        let rootOffset = Int32(buffer.read(def: UInt32.self, position: 0))
        let root = GenerationConfiguration(buffer, o: rootOffset)

        XCTAssertEqual(root.originalImageWidth, 0)
        XCTAssertEqual(root.originalImageHeight, 0)
        XCTAssertEqual(root.targetImageWidth, 0)
        XCTAssertEqual(root.targetImageHeight, 0)
        XCTAssertEqual(root.negativeOriginalImageWidth, 0)
        XCTAssertEqual(root.negativeOriginalImageHeight, 0)
    }

    func testConfigurationCreation() throws {
        let config = DrawThingsConfiguration(
            width: 512,
            height: 512,
            steps: 20,
            model: "sd_xl_base_1.0.safetensors",
            guidanceScale: 7.0
        )
        
        XCTAssertEqual(config.width, 512)
        XCTAssertEqual(config.height, 512)
        XCTAssertEqual(config.steps, 20)
        XCTAssertEqual(config.guidanceScale, 7.0)
    }
    
    func testSamplerTypes() {
        XCTAssertEqual(SamplerType.ddim.rawValue, 2)
        XCTAssertEqual(SamplerType.eulera.rawValue, 1)
        XCTAssertEqual(SamplerType.dpmpp2mkarras.rawValue, 0)
    }
    
    func testGenerationStageDescriptions() {
        XCTAssertEqual(GenerationStage.textEncoding.description, "Encoding text prompt...")
        XCTAssertEqual(GenerationStage.sampling(step: 5).description, "Generating image (step 5)...")
        XCTAssertEqual(GenerationStage.imageDecoding.description, "Decoding generated image...")
    }

    func testLatentModelFamilyDetection() {
        // SD 1.x/2.x/SVD must be distinguished from SDXL (different 4-channel coefficients).
        XCTAssertEqual(LatentModelFamily.detect(from: "v1"), .sd1)
        XCTAssertEqual(LatentModelFamily.detect(from: "v2"), .sd1)
        XCTAssertEqual(LatentModelFamily.detect(from: "svd_xt_1.1.safetensors"), .sd1)
        XCTAssertEqual(LatentModelFamily.detect(from: "sd_xl_base_1.0.safetensors"), .sdxl)
        XCTAssertEqual(LatentModelFamily.detect(from: "sdxlBase"), .sdxl)
        XCTAssertEqual(LatentModelFamily.detect(from: "pixart"), .sdxl)

        // HiDream-O1 (patch decode) must not be confused with HiDream-I1 (Flux coefficients).
        XCTAssertEqual(LatentModelFamily.detect(from: "hidreamo1"), .hiDreamO1)
        XCTAssertEqual(LatentModelFamily.detect(from: "hidream_o1"), .hiDreamO1)
        XCTAssertEqual(LatentModelFamily.detect(from: "hidreami1"), .flux)

        // New models reusing existing coefficient families.
        XCTAssertEqual(LatentModelFamily.detect(from: "cosmos2_5_2b"), .qwen)
        XCTAssertEqual(LatentModelFamily.detect(from: "ernieImage"), .flux2)
        XCTAssertEqual(LatentModelFamily.detect(from: "seedvr2_3b"), .flux)

        // Newly recognized older families.
        XCTAssertEqual(LatentModelFamily.detect(from: "kandinsky21"), .kandinsky)
        XCTAssertEqual(LatentModelFamily.detect(from: "wurstchenStageC"), .wurstchen)

        // Regression checks on existing routing.
        XCTAssertEqual(LatentModelFamily.detect(from: "qwenImage"), .qwen)
        XCTAssertEqual(LatentModelFamily.detect(from: "flux1"), .flux)
        XCTAssertEqual(LatentModelFamily.detect(from: "wan22_5b"), .wan22)
        XCTAssertEqual(LatentModelFamily.detect(from: "totally-unknown-model"), .unknown)
    }

    func testLatentModelFamilyChannels() {
        XCTAssertEqual(LatentModelFamily.sd1.latentChannels, 4)
        XCTAssertEqual(LatentModelFamily.kandinsky.latentChannels, 4)
        XCTAssertEqual(LatentModelFamily.wurstchen.latentChannels, 4)
        XCTAssertEqual(LatentModelFamily.flux2.latentChannels, 32)
        XCTAssertEqual(LatentModelFamily.wan22.latentChannels, 48)
        XCTAssertEqual(LatentModelFamily.hiDreamO1.latentChannels, 3 * 32 * 32)
    }
}
