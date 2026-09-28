# DrawThingsKit reference

App-level state, all `@MainActor @Observable`. `import DrawThingsKit` also imports DrawThingsClient.

```swift
import DrawThingsKit

@State private var connection = ConnectionManager()
@State private var configuration = ConfigurationManager()

await connection.connectToDefault()                   // or connect(to: profile)
guard let service = connection.activeService else { return }
configuration.selectedCheckpoint = connection.modelsManager.baseModels.first
let request = configuration.makeRequest(image: nil, mask: nil, hints: [])
```

## ConnectionManager and profiles

- `ServerProfile(name:host:port:useTLS:sharedSecret:isDefault:)` or `ServerProfile(name:address:)`;
  `address`, `connectionOptions`. `ServerProfile.localhost` is `localhost:7859` with TLS.
- `ConnectionManager(storage: ProfileStorage())` loads saved profiles (creating a localhost profile
  on first launch). `profiles`, `activeProfile`, `defaultProfile`, `connectionState`
  (`.disconnected`, `.connecting`, `.connected`, `.error(String)`), `serverRequiresSharedSecret`,
  `activeService`, `modelsManager`.
- `addProfile`, `updateProfile`, `deleteProfile`, `setDefault`, `connect(to:)`, `connectToDefault()`,
  `reconnect()`, `disconnect()` (closes the connection).
- `ProfileStorage` keeps profiles in `UserDefaults` and shared secrets in the Keychain
  (`KeychainSecretStore`); pass `ProfileStorage(secrets:)` a custom `SecretStore` for tests.

## ModelsManager

Filled from the server's echo when model browsing is on. `localCheckpoints`, `localLoRAs`,
`localControlNets`, `localTextualInversions`, `localUpscalers`. With `bridgeMode = true` (default)
the lists (`checkpoints`, `loras`, `controlNets`, `textualInversions`, `upscalers`) also include the
official and community models available through Draw Things+ (`CloudModels`, bundled). `baseModels`,
`refinerModels`, `selectedCheckpoint`, `compatibleLoRAs`/`compatibleControlNets`/
`compatibleTextualInversions` (matching the checkpoint's version), `checkpoint(forFile:)`,
`modelFamily(forFile:)`. Model types: `CheckpointModel` (`name`, `file`, `version`, `family`,
`framesPerSecond`, `audioSampleRate`, `source`), `LoRAModel`, `ControlNetModel`,
`TextualInversionModel`, `UpscalerModel`; `ModelSource` is `.local`, `.official` or `.community`.

## ConfigurationManager

`activeConfiguration`, `prompt`, `negativePrompt`, `selectedCheckpoint`, `selectedRefiner`,
`selectedLoRAs: [LoRAConfiguration]`, `selectedControls: [ControlNetConfiguration]`.
`makeRequest(image:mask:hints:)` syncs the selections into the configuration and builds a
`GenerationRequest`. `loadFromJSON(_:) -> Bool` (merges Draw Things JSON) then
`resolveModels(from: modelsManager)`; `exportToJSON()`; `resetToDefaults()`. For copy and paste,
move the JSON through `NSPasteboard`/`UIPasteboard` in the app.

Presets: `DimensionPresets.all`/`.common`, `SamplerPresets.all`/`name(for:)`,
`ConfigurationDefaults`, and `SavedConfiguration` (a SwiftData `@Model` storing a name, tags and
configuration JSON).
