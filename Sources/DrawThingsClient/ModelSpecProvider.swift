import Foundation
import SwiftProtobuf

/// Provides model specifications from bundled + remote sources, mirroring
/// the upstream Draw Things app's ModelZoo.  The gRPC server needs these
/// specs to determine the correct model version, modifier, objective and
/// latent-space parameters.  Without them it falls back to SD v1 defaults
/// and produces noise for newer model families (Flux.2 Klein, Krea 2, etc.).
///
/// The Draw Things app downloads the live model list from
/// `https://models.drawthings.ai/models.json` at startup.  We do the same,
/// falling back to the bundled snapshot for offline use.
enum ModelSpecProvider {

    /// Specs index: model filename → JSON dictionary.
    /// Populated from the bundled models.json, then enriched with the live
    /// API data once ``fetchRemoteSpecs()`` completes.
    private static var specsByFile: [String: Any] = {
        return parseSpecs(from: bundledModelsJSON)
    }()

    private static let lock = NSLock()

    // MARK: - Bundled data

    private static let bundledModelsJSON: Data = {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            DrawThingsClientLogger.notice("models.json not found in bundle — override will be empty")
            return Data()
        }
        return data
    }()

    // MARK: - Remote fetch

    private static var hasFetchedRemote = false

    /// Download the live model list from the Draw Things API and merge it
    /// into the specs index.  This is the same URL the Draw Things app uses
    /// (``ModelZoo+Downloads.swift`` line 64).  Safe to call multiple times;
    /// only the first call performs the network request.
    static func fetchRemoteSpecs() async {
        lock.lock()
        let alreadyFetched = hasFetchedRemote
        if !alreadyFetched { hasFetchedRemote = true }
        lock.unlock()
        guard !alreadyFetched else { return }

        let url = URL(string: "https://models.drawthings.ai/models.json")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let remote = parseSpecs(from: data)
            lock.lock()
            // Merge: remote specs override bundled ones for the same file.
            for (file, spec) in remote {
                specsByFile[file] = spec
            }
            lock.unlock()
            DrawThingsClientLogger.debug("Fetched \(remote.count) model specs from remote API")
        } catch {
            DrawThingsClientLogger.notice("Failed to fetch remote models.json: \(error.localizedDescription)")
        }
    }

    // MARK: - Lookup

    /// Build a ``MetadataOverride`` that includes the specification for
    /// the given model filename (and optionally LoRA filenames).
    /// This mirrors ``ImageGeneratorUtils.metadataOverride`` in the upstream app.
    static func overrideForModel(_ modelFile: String, loraFiles: [String] = []) -> MetadataOverride {
        lock.lock()
        var specs = [[String: Any]]()
        if let spec = specsByFile[modelFile] as? [String: Any] {
            specs.append(spec)
        }
        for lora in loraFiles {
            if let spec = specsByFile[lora] as? [String: Any] {
                specs.append(spec)
            }
        }
        lock.unlock()

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

    /// Returns true if a specification is available (bundled or remote)
    /// for the given model filename.
    static func hasSpec(for modelFile: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return specsByFile[modelFile] != nil
    }

    // MARK: - Helpers

    private static func parseSpecs(from data: Data) -> [String: Any] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }
        var dict = [String: Any]()
        for entry in array {
            if let file = entry["file"] as? String {
                dict[file] = entry
            }
        }
        return dict
    }
}
