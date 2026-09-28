import DrawThingsKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Prompt, model and size, and a Generate button that adds a job to the queue.
///
/// Sampler, guidance and shift matter per model; a model given unsuitable ones can fail on the
/// server. The easiest way to get them right is to copy the configuration from Draw Things
/// ("Copy Configuration") and paste it here.
struct GenerateView: View {
    @Environment(AppModel.self) private var model
    @Environment(ConnectionManager.self) private var connection
    @Environment(ConfigurationManager.self) private var configuration
    @State private var pasteMessage: String?

    var body: some View {
        @Bindable var configuration = configuration
        @Bindable var models = connection.modelsManager
        Form {
            Section("Prompt") {
                TextField("Prompt", text: $configuration.prompt, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Negative prompt", text: $configuration.negativePrompt, axis: .vertical)
            }
            Section("Model") {
                Toggle("Include Draw Things+ models", isOn: $models.bridgeMode)
                Picker("Model", selection: $configuration.selectedCheckpoint) {
                    Text(configuration.activeConfiguration.model).tag(CheckpointModel?.none)
                    ForEach(models.baseModels) { checkpoint in
                        Text(checkpoint.name).tag(Optional(checkpoint))
                    }
                }
                LabeledContent("Sampler", value: SamplerPresets.name(for: configuration.activeConfiguration.sampler))
                LabeledContent("Guidance", value: configuration.activeConfiguration.guidanceScale.formatted())
            }
            Section("Size") {
                Picker("Size", selection: sizeBinding) {
                    ForEach(DimensionPresets.all) { preset in
                        Text("\(preset.name) (\(preset.width)×\(preset.height))").tag(preset.id)
                    }
                    if !DimensionPresets.all.contains(where: { $0.id == sizeBinding.wrappedValue }) {
                        Text("\(configuration.activeConfiguration.width)×\(configuration.activeConfiguration.height)")
                            .tag(sizeBinding.wrappedValue)
                    }
                }
                Stepper("Steps: \(configuration.activeConfiguration.steps)", value: $configuration.activeConfiguration.steps, in: 1...150)
            }
            Section {
                Button("Paste Configuration from Draw Things", systemImage: "doc.on.clipboard") { paste() }
                if let pasteMessage { Text(pasteMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Button("Generate", systemImage: "wand.and.stars") {
                    model.queue?.enqueue(configuration.makeRequest())
                }
                .disabled(model.queue == nil || configuration.prompt.isEmpty)
            }
            if let queue = model.queue {
                Section("Latest") {
                    if let job = queue.current {
                        ProgressView(value: queue.progress?.fractionCompleted ?? 0) {
                            Text(queue.progress?.stage.description ?? job.name)
                        }
                        if let preview = queue.preview { ResultImage(image: preview).frame(maxHeight: 300) }
                    } else if let image = queue.finished.last(where: { $0.status == .completed })?.result?.images.first {
                        ResultImage(image: image).frame(maxHeight: 300)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Generate")
    }

    /// The size as a preset ID ("name-WxH"), or "WxH" when it matches no preset.
    private var sizeBinding: Binding<String> {
        Binding {
            let config = configuration.activeConfiguration
            return DimensionPresets.all.first { $0.width == config.width && $0.height == config.height }?.id
                ?? "\(config.width)x\(config.height)"
        } set: { id in
            guard let preset = DimensionPresets.all.first(where: { $0.id == id }) else { return }
            configuration.activeConfiguration.width = Int32(preset.width)
            configuration.activeConfiguration.height = Int32(preset.height)
        }
    }

    private func paste() {
        #if os(macOS)
        let text = NSPasteboard.general.string(forType: .string)
        #else
        let text = UIPasteboard.general.string
        #endif
        guard let text, configuration.loadFromJSON(text) else {
            pasteMessage = "The clipboard doesn't hold a Draw Things configuration."
            return
        }
        configuration.resolveModels(from: connection.modelsManager)
        pasteMessage = "Pasted: \(configuration.activeConfiguration.model)"
    }
}
