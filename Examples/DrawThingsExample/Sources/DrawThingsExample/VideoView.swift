import AVKit
import DrawThingsVideoKit
import SwiftUI

/// Video settings, assembly progress, the latest video and the frames it was made from.
/// Rebuilds DrawThingsVideoKit 0.3's `VideoConfigurationView`, `VideoAssemblyProgressView` and
/// `VideoFrameCollectionView` on `VideoProcessor`.
///
/// Video results from the queue are assembled automatically (see `AppModel`).
struct VideoView: View {
    @Environment(AppModel.self) private var model
    @Environment(VideoProcessor.self) private var video
    @State private var player: AVPlayer?

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Settings") {
                Picker("Codec", selection: $model.videoSettings.codec) {
                    ForEach(VideoCodec.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Quality", selection: $model.videoSettings.quality) {
                    ForEach(VideoQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Frame interpolation", selection: interpolationFactor) {
                    Text("Off").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                    Text("4×").tag(4)
                }
                Picker("Super resolution", selection: superResolutionFactor) {
                    Text("Off").tag(1)
                    Text("2×").tag(2)
                }
                LabeledContent("Interpolation method", value: FrameInterpolator.isVTFrameProcessorAvailable ? "Machine learning" : "Cross-dissolve")
            }

            if video.isAssembling {
                Section("Assembling") {
                    ProgressView(value: video.assemblyProgress)
                }
            }
            if let error = video.lastError {
                Section { Text(error.localizedDescription).foregroundStyle(.red) }
            }

            if let url = video.lastOutputURL {
                Section("Latest video") {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .onAppear { player = AVPlayer(url: url) }
                        .onChange(of: url) { player = AVPlayer(url: url) }
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !video.collectedFrames.isEmpty {
                Section("Collected frames (\(video.collectedFrames.count))") {
                    ScrollView(.horizontal) {
                        LazyHStack {
                            ForEach(Array(video.collectedFrames.allCGImages().enumerated()), id: \.offset) { _, frame in
                                ResultImage(image: frame).frame(height: 80)
                            }
                        }
                    }
                    Button("Assemble Again") {
                        Task {
                            var settings = model.videoSettings
                            settings.outputURL = AppModel.videosFolder.appending(path: "\(UUID().uuidString).mp4")
                            // A failure shows in video.lastError.
                            _ = try? await video.assembleCollectedFrames(configuration: settings)
                        }
                    }
                    .disabled(video.isAssembling)
                }
            }

            if video.lastOutputURL == nil && video.collectedFrames.isEmpty {
                Text("Generate with a video model (for example Wan or MiniMax H3) and the video appears here.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Video")
    }

    /// Interpolation as a factor; the output frame rate keeps the video's duration.
    private var interpolationFactor: Binding<Int> {
        Binding {
            model.videoSettings.interpolation.factor
        } set: { factor in
            model.videoSettings.interpolation = factor > 1 ? .enabled(factor: factor) : .disabled
            model.videoSettings.frameRate = model.videoSettings.sourceFrameRate * factor
        }
    }

    private var superResolutionFactor: Binding<Int> {
        Binding {
            model.videoSettings.superResolution.factor
        } set: { factor in
            model.videoSettings.superResolution = factor > 1 ? .enabled(factor: factor) : .disabled
        }
    }
}
