import Foundation
import Testing
@testable import DrawThingsClient
@testable import DrawThingsKit

@Suite("ServerProfile")
struct ServerProfileTests {
    @Test func parsesAddresses() {
        let named = ServerProfile(name: "A", address: "example.com:8080", useTLS: false)
        #expect(named.host == "example.com")
        #expect(named.port == 8080)
        #expect(named.address == "example.com:8080")

        let noPort = ServerProfile(name: "B", address: "example.com")
        #expect(noPort.port == 7859)

        let ipv6 = ServerProfile(name: "C", address: "[fe80::1]:7860")
        #expect(ipv6.host == "fe80::1")
        #expect(ipv6.port == 7860)
        #expect(ipv6.address == "[fe80::1]:7860")
    }

    @Test func connectionOptionsCarryTLSAndSecret() {
        let secure = ServerProfile(name: "S", useTLS: true, sharedSecret: "s3cret").connectionOptions
        #expect(secure.sharedSecret == "s3cret")
        if case .tls = secure.security {} else { Issue.record("expected TLS") }
        if case .plaintext = ServerProfile(name: "P", useTLS: false).connectionOptions.security {} else { Issue.record("expected plaintext") }
    }

    @Test func localhostDefaults() {
        let profile = ServerProfile.localhost
        #expect(profile.host == "localhost")
        #expect(profile.port == 7859)
        #expect(profile.useTLS)
        #expect(profile.isDefault)
    }

    @Test func storageRoundTrip() throws {
        let suite = "DrawThingsKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = ProfileStorage(userDefaults: defaults, keyPrefix: "test")
        #expect(storage.loadProfiles().isEmpty)

        let profiles = [ServerProfile(name: "One", host: "a"), ServerProfile(name: "Two", host: "b", sharedSecret: "x")]
        storage.saveProfiles(profiles)
        #expect(storage.loadProfiles() == profiles)
        storage.clearProfiles()
        #expect(storage.loadProfiles().isEmpty)
    }
}

@Suite("ConnectionManager")
@MainActor
struct ConnectionManagerTests {
    private func manager() throws -> (ConnectionManager, () -> Void) {
        let suite = "DrawThingsKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (ConnectionManager(storage: ProfileStorage(userDefaults: defaults, keyPrefix: "test")),
                { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func startsWithALocalhostProfile() throws {
        let (manager, cleanup) = try manager()
        defer { cleanup() }
        #expect(manager.profiles.map(\.host) == ["localhost"])
        #expect(manager.defaultProfile?.host == "localhost")
        #expect(manager.connectionState == .disconnected)
        #expect(manager.activeService == nil)
    }

    @Test func connectsWithTheSharedSecretAndLoadsModels() async throws {
        // One checkpoint lacks a name: it is skipped, the rest still load.
        let models = #"[{"name":"Flux","file":"flux.ckpt","version":"flux1"},{"file":"broken.ckpt"},{"name":"Wan","file":"wan.ckpt","version":"wan_v2.1_14b"}]"#
        let server = try await FakeDrawThingsServer(echoReply: EchoReply.with {
            $0.message = "HELLO"
            $0.override = .with {
                $0.models = Data(models.utf8)
                $0.loras = Data(#"[{"name":"Style","file":"style.safetensors","version":"flux1"}]"#.utf8)
            }
        })
        defer { Task { await server.stop() } }
        let (manager, cleanup) = try manager()
        defer { cleanup() }
        manager.modelsManager.bridgeMode = false

        await manager.connect(to: ServerProfile(name: "Test", host: "127.0.0.1", port: server.port, useTLS: false, sharedSecret: "s3cret"))

        #expect(manager.connectionState == .connected)
        #expect(manager.activeService != nil)
        #expect(server.record.echoRequests.first?.sharedSecret == "s3cret")
        #expect(manager.modelsManager.checkpoints.map(\.file) == ["flux.ckpt", "wan.ckpt"])
        #expect(manager.modelsManager.loras.map(\.file) == ["style.safetensors"])
        #expect(manager.modelsManager.modelFamily(forFile: "wan.ckpt") == .wan21)

        manager.disconnect()
        #expect(manager.connectionState == .disconnected)
        #expect(manager.activeService == nil)
        #expect(manager.modelsManager.localCheckpoints.isEmpty)
    }

    @Test func missingSecretIsReported() async throws {
        let server = try await FakeDrawThingsServer(echoReply: EchoReply.with { $0.sharedSecretMissing = true })
        defer { Task { await server.stop() } }
        let (manager, cleanup) = try manager()
        defer { cleanup() }

        await manager.connect(to: ServerProfile(name: "Test", host: "127.0.0.1", port: server.port, useTLS: false))
        #expect(manager.serverRequiresSharedSecret)
        #expect(manager.connectionState.errorMessage != nil)
        #expect(manager.activeService == nil)
    }

    @Test func profilesKeepOneDefault() throws {
        let (manager, cleanup) = try manager()
        defer { cleanup() }
        let second = ServerProfile(name: "Second", host: "b", isDefault: true)
        manager.addProfile(second)
        #expect(manager.profiles.filter(\.isDefault).map(\.id) == [second.id])

        manager.deleteProfile(second)
        #expect(manager.profiles.filter(\.isDefault).count == 1)
    }
}

@Suite("ModelsManager")
@MainActor
struct ModelsManagerTests {
    @Test func cloudCatalogsLoad() {
        #expect(!CloudModels.officialCheckpoints.isEmpty)
        #expect(!CloudModels.communityCheckpoints.isEmpty)
        #expect(CloudModels.officialCheckpoints.allSatisfy { $0.source == .official })
    }

    @Test func bridgeModeMergesCloudFirst() {
        let manager = ModelsManager()
        let official = CloudModels.officialCheckpoints[0]
        manager.updateFromMetadata(MetadataOverride.with {
            $0.models = Data(#"[{"name":"Local copy","file":"\#(official.file)"},{"name":"Mine","file":"mine.ckpt"}]"#.utf8)
        })
        #expect(manager.checkpoints.first { $0.file == official.file }?.source == .official)
        #expect(manager.checkpoints.contains { $0.file == "mine.ckpt" })

        manager.bridgeMode = false
        #expect(manager.checkpoints.map(\.file) == [official.file, "mine.ckpt"])
    }

    @Test func compatibilityFollowsTheCheckpointVersion() {
        let manager = ModelsManager()
        manager.bridgeMode = false
        manager.updateFromMetadata(MetadataOverride.with {
            $0.loras = Data(#"[{"name":"XL","file":"xl.safetensors","version":"sdxl_base_v0.9"},{"name":"F","file":"f.safetensors","version":"flux1"}]"#.utf8)
        })
        manager.selectedCheckpoint = CheckpointModel(name: "SDXL", file: "sdxl.ckpt", version: "sdxlBase")
        #expect(manager.compatibleLoRAs.map(\.file) == ["xl.safetensors"])
    }

    @Test func frameRatesComeFromTheClient() {
        #expect(CheckpointModel(name: "", file: "a.ckpt", version: "wan_v2.2_5b").framesPerSecond == 24)
        #expect(CheckpointModel(name: "", file: "a.ckpt", version: "svd_i2v").framesPerSecond == 30)
        #expect(CheckpointModel(name: "", file: "a.ckpt", version: "hunyuan_video").framesPerSecond == 30)
        #expect(CheckpointModel(name: "", file: "a.ckpt", version: "flux1").framesPerSecond == nil)
        #expect(CheckpointModel(name: "", file: "a.ckpt", version: "ltx2_3").audioSampleRate == 48_000)
    }
}

@Suite("ConfigurationManager")
@MainActor
struct ConfigurationManagerTests {
    @Test func requestsCarryPromptModelsAndLoRAs() {
        let manager = ConfigurationManager()
        manager.prompt = "a fox"
        manager.negativePrompt = "blurry"
        manager.selectedCheckpoint = CheckpointModel(name: "Z", file: "z_image_turbo_1.0_q8p.ckpt", version: "z_image")
        manager.selectedLoRAs = [
            LoRAConfiguration(lora: LoRAModel(name: "On", file: "on.safetensors"), weight: 0.5),
            LoRAConfiguration(lora: LoRAModel(name: "Off", file: "off.safetensors"), enabled: false),
        ]

        let request = manager.makeRequest()
        #expect(request.prompt == "a fox")
        #expect(request.negativePrompt == "blurry")
        #expect(request.configuration.model == "z_image_turbo_1.0_q8p.ckpt")
        #expect(request.configuration.loras.map(\.file) == ["on.safetensors"])
        #expect(request.configuration.loras.first?.weight == 0.5)
        #expect(request.modelFamily == .zImage)
    }

    @Test func jsonRoundTripAndModelResolution() throws {
        let manager = ConfigurationManager()
        manager.activeConfiguration = DrawThingsConfiguration(width: 768, height: 512, steps: 8, model: "mine.ckpt")
        let json = try #require(manager.exportToJSON())

        let other = ConfigurationManager()
        #expect(other.loadFromJSON(json))
        #expect(other.activeConfiguration.width == 768)
        #expect(!other.loadFromJSON("not json"))

        let models = ModelsManager()
        models.bridgeMode = false
        models.updateFromMetadata(MetadataOverride.with { $0.models = Data(#"[{"name":"Mine","file":"mine.ckpt"}]"#.utf8) })
        other.resolveModels(from: models)
        #expect(other.selectedCheckpoint?.file == "mine.ckpt")
    }
}

@Suite("Presets")
struct PresetTests {
    @Test func everySamplerHasAName() {
        let samplers = (SamplerType.min.rawValue...SamplerType.max.rawValue).compactMap(SamplerType.init(rawValue:))
        #expect(samplers.count == Int(SamplerType.max.rawValue - SamplerType.min.rawValue) + 1)
        #expect(samplers.allSatisfy { SamplerPresets.name(for: $0) != "Unknown" })
        #expect(SamplerPresets.name(for: .dpmpp2mkarras) == "DPM++ 2M Karras")
    }

    @Test func dimensionPresets() {
        #expect(DimensionPresets.square1024.width == 1024)
        #expect(DimensionPresets.hd1280x720.height == 720)
        #expect(Set(DimensionPresets.all.map(\.id)).count == DimensionPresets.all.count)
    }
}
