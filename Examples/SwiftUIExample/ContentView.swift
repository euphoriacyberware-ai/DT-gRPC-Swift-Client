import SwiftUI
import DrawThingsClient

struct ContentView: View {
    @State private var session: DrawThingsSession?
    @State private var address = "localhost:7859"
    @State private var prompt = "A beautiful sunset over mountains"
    @State private var negativePrompt = "low quality, blurry"
    @State private var model = "z_image_turbo_1.0_q8p.ckpt"
    @State private var images: [CGImage] = []
    @State private var generation: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionSection
            inputSection
            progressSection
            imageSection
            Spacer()
        }
        .padding()
        .frame(minWidth: 560, minHeight: 640)
        .task { await connect() }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        HStack {
            Circle()
                .fill(session?.isConnected == true ? .green : .red)
                .frame(width: 10, height: 10)
            TextField("Server address", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await connect() } }
            Button("Connect") { Task { await connect() } }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Prompt", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            TextField("Negative prompt", text: $negativePrompt)
                .textFieldStyle(.roundedBorder)
            TextField("Model file", text: $model)
                .textFieldStyle(.roundedBorder)
            HStack {
                if session?.isGenerating == true {
                    Button("Cancel", role: .cancel) { session?.cancel() }
                } else {
                    Button("Generate") { startGeneration() }
                        .buttonStyle(.borderedProminent)
                        .disabled(session?.isConnected != true || prompt.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let session, let progress = session.progress {
            VStack(alignment: .leading) {
                Text(progress.stage.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                if let preview = session.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                }
            }
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading) {
            if !images.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 256, height: 256)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { save(image, index: index) }
                                .help("Click to save")
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func connect() async {
        do {
            let session = try DrawThingsSession(address: address)
            self.session = session
            await session.connect()
            errorMessage = session.lastError?.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startGeneration() {
        guard let session else { return }
        errorMessage = nil
        let configuration = DrawThingsConfiguration(
            width: 1024, height: 1024, steps: 8, model: model,
            sampler: .dpmpp2mtrailing, guidanceScale: 1, shift: 3
        )
        generation = Task {
            do {
                let result = try await session.generate(
                    GenerationRequest(prompt: prompt, negativePrompt: negativePrompt, configuration: configuration)
                )
                images = result.images
            } catch is CancellationError {
                // Cancelled by the user.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save(_ image: CGImage, index: Int) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated_image_\(index + 1).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageHelpers.saveImage(image, to: url, format: .png)
        } catch {
            errorMessage = "Failed to save image: \(error.localizedDescription)"
        }
        #endif
    }
}

#Preview {
    ContentView()
}
