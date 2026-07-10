import XCTest
import FlatBuffers
@testable import DrawThingsClient

final class DrawThingsClientTests: XCTestCase {

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