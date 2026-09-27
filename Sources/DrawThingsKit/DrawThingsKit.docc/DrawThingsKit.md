# ``DrawThingsKit``

App-level state for Draw Things clients: saved servers, the model catalog and the active
configuration.

## Overview

DrawThingsKit holds the parts of a Draw Things app that sit between the user and a
`DrawThingsService`. Its types are `@Observable`, so SwiftUI views that read them update on their
own; the library itself contains no views. Importing DrawThingsKit also imports DrawThingsClient.

```swift
import DrawThingsKit
import DrawThingsQueue

@State private var connection = ConnectionManager()
@State private var configuration = ConfigurationManager()

// Connect to the default saved server (a localhost profile is created on first launch).
await connection.connectToDefault()
guard let service = connection.activeService else { return }

// Pick a model from what the server reported, then generate.
configuration.selectedCheckpoint = connection.modelsManager.baseModels.first
let queue = GenerationQueue(service: service)
queue.enqueue(configuration.makeRequest())
```

### Servers

``ServerProfile`` stores a server's address, TLS setting and shared secret, and
``ServerProfile/connectionOptions`` turns them into the client's `ConnectionOptions`.
``ConnectionManager`` keeps the profiles (in `UserDefaults` through ``ProfileStorage``), connects
with an echo that also checks the shared secret, and exposes ``ConnectionManager/activeService``.

> Important: Profiles, including their shared secrets, are stored in `UserDefaults` in plain text.

### Models

``ModelsManager`` lists the checkpoints, LoRAs, ControlNets, textual inversions and upscalers the
server reports when model browsing is on. With ``ModelsManager/bridgeMode`` it adds the official
and community models available through Draw Things+ (``CloudModels``, bundled with the package).
Compatibility filters such as ``ModelsManager/compatibleLoRAs`` follow the selected checkpoint's
version.

### Configuration

``ConfigurationManager`` holds the prompt, the selected models and LoRAs, and the
`DrawThingsConfiguration`. ``ConfigurationManager/makeRequest(image:mask:hints:)`` builds a
`GenerationRequest` from them. ``ConfigurationManager/exportToJSON()`` and
``ConfigurationManager/loadFromJSON(_:)`` read and write Draw Things JSON; pass it to and from the
system pasteboard for copy and paste with the app.

## Topics

### Servers

- ``ConnectionManager``
- ``ConnectionState``
- ``ServerProfile``
- ``ProfileStorage``

### Models

- ``ModelsManager``
- ``CloudModels``
- ``CheckpointModel``
- ``LoRAModel``
- ``ControlNetModel``
- ``TextualInversionModel``
- ``UpscalerModel``
- ``ModelSource``
- ``ModelVersionNormalizer``

### Configuration

- ``ConfigurationManager``
- ``LoRAConfiguration``
- ``ControlNetConfiguration``
- ``SavedConfiguration``
- ``ConfigurationDefaults``
- ``DimensionPresets``
- ``DimensionPreset``
- ``SamplerPresets``
- ``SamplerInfo``
