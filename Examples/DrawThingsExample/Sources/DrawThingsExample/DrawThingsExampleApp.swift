import DrawThingsKit
import DrawThingsQueue
import DrawThingsVideoKit
import SwiftUI

@main
struct DrawThingsExampleApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(model.connection)
                .environment(model.configuration)
                .environment(model.video)
                .task { await model.connectToDefault() }
        }
    }
}

#if os(macOS)
/// Run from a Swift package, the app has no bundle, so macOS starts it as a background process:
/// no Dock icon, and its window stays behind other apps. Make it a regular app and bring it forward.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
#endif

/// Ties the library's observable objects together: a connection, the configuration being edited,
/// a queue on the connected server, and a video processor fed by the queue's results.
@MainActor
@Observable
final class AppModel {
    let connection = ConnectionManager()
    let configuration = ConfigurationManager()
    let video: VideoProcessor
    /// Created on the first successful connection; later connections switch its service.
    private(set) var queue: GenerationQueue?

    nonisolated static let appFolder = URL.applicationSupportDirectory.appending(path: "DrawThingsExample", directoryHint: .isDirectory)
    #if os(macOS)
    nonisolated static let videosFolder = URL.moviesDirectory.appending(path: "DrawThingsExample", directoryHint: .isDirectory)
    #else
    nonisolated static let videosFolder = URL.documentsDirectory.appending(path: "Videos", directoryHint: .isDirectory)
    #endif

    init() {
        try? FileManager.default.createDirectory(at: Self.videosFolder, withIntermediateDirectories: true)
        video = VideoProcessor(configuration: VideoProcessorConfiguration(
            autoAssemble: true,
            defaultVideoConfiguration: VideoConfiguration(outputURL: Self.videosFolder.appending(path: "video.mp4"))
        ))
        videoSettings = VideoConfiguration(outputURL: Self.videosFolder.appending(path: "video.mp4"))
        applyVideoSettings()
        // A preset that suits Z Image Turbo; paste a configuration from Draw Things for other models.
        configuration.activeConfiguration = DrawThingsConfiguration(
            width: 1024, height: 1024, steps: 8, model: "z_image_turbo_1.0_q8p.ckpt",
            sampler: .dpmpp2mtrailing, guidanceScale: 1, shift: 3
        )
    }

    /// Encoding settings for new videos (the output file is named after each job).
    var videoSettings: VideoConfiguration {
        didSet { applyVideoSettings() }
    }

    private func applyVideoSettings() {
        let settings = videoSettings
        video.configuration.configurationProvider = { jobID in
            var configuration = settings
            configuration.outputURL = AppModel.videosFolder.appending(path: "\(jobID.uuidString).mp4")
            return configuration
        }
    }

    func connectToDefault() async {
        guard let profile = connection.defaultProfile else { return }
        await connect(to: profile)
    }

    func connect(to profile: ServerProfile) async {
        await connection.connect(to: profile)
        guard let service = connection.activeService else { return }
        if let queue {
            queue.service = service
            if queue.pauseReason != nil { queue.resume() }
        } else {
            let queue = GenerationQueue(service: service, storage: QueueStorage(fileURL: Self.appFolder.appending(path: "queue.json")))
            self.queue = queue
            video.connect(to: queue.results)
            try? await queue.restore()
        }
    }
}
