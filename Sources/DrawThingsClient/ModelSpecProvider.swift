import Foundation
import SwiftProtobuf

/// Provides model specifications from the bundled models.json, mirroring
/// the upstream Draw Things app's ModelZoo.  The gRPC server needs these
/// specs to determine the correct model version, modifier, objective and
/// latent-space parameters.  Without them it falls back to SD v1 defaults
/// and produces noise for newer model families (Flux.2 Klein, Krea 2, etc.).
enum ModelSpecProvider {

    /// Raw JSON bytes for all known model specifications (snake_case keys).
    /// Loaded once from the bundled models.json resource.
    static let modelsJSON: Data = {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            DrawThingsClientLogger.notice("models.json not found in bundle — override will be empty")
            return Data()
        }
        return data
    }()

    // Pre-parsed index: model filename → position in the JSON array so we
    // can extract individual specs cheaply.
    private static let specsByFile: [String: Any] = {
        guard let array = try? JSONSerialization.jsonObject(with: modelsJSON) as? [[String: Any]]
        else { return [:] }
        var dict = [String: Any]()
        for entry in array {
            if let file = entry["file"] as? String {
                dict[file] = entry
            }
        }
        return dict
    }()

    /// Build a ``MetadataOverride`` that includes the specification for
    /// the given model filename (and optionally LoRA filenames).
    /// This mirrors ``ImageGeneratorUtils.metadataOverride`` in the upstream app.
    static func overrideForModel(_ modelFile: String, loraFiles: [String] = []) -> MetadataOverride {
        var specs = [[String: Any]]()
        if let spec = specsByFile[modelFile] as? [String: Any] {
            specs.append(spec)
        }
        // The server also needs LoRA specs, but those are rarely missing
        // from builtins.  We include them when available.
        for lora in loraFiles {
            if let spec = specsByFile[lora] as? [String: Any] {
                specs.append(spec)
            }
        }

        var override = MetadataOverride()
        if !specs.isEmpty {
            // Re-serialize just the matched specs as a JSON array.
            // models.json is already in snake_case, which is what the server's
            // JSONDecoder (with .convertFromSnakeCase) expects.
            if let data = try? JSONSerialization.data(withJSONObject: specs) {
                override.models = data
            }
        }
        return override
    }

    /// Returns true if the bundled models.json has a specification for
    /// the given model filename.
    static func hasSpec(for modelFile: String) -> Bool {
        specsByFile[modelFile] != nil
    }
}
