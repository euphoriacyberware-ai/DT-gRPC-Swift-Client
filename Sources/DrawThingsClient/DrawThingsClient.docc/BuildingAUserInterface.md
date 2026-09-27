# Building a user interface

Drive SwiftUI views from ``DrawThingsSession``.

## Overview

The library ships no views. Its state types are `@Observable`, so SwiftUI tracks the properties a
view reads and redraws it when they change; the library doesn't need to import SwiftUI for that.

``DrawThingsSession`` wraps a ``DrawThingsService`` and mirrors its event stream into observable
properties: ``DrawThingsSession/progress``, ``DrawThingsSession/preview``,
``DrawThingsSession/isGenerating`` and ``DrawThingsSession/lastResult``.

```swift
import SwiftUI
import DrawThingsClient

struct ContentView: View {
    @State private var session = try! DrawThingsSession(address: "localhost:7859")
    @State private var image: CGImage?

    var body: some View {
        VStack {
            if let progress = session.progress {
                ProgressView(value: progress.fractionCompleted ?? 0) {
                    Text(progress.stage.description)
                }
            }
            if let shown = session.preview ?? image {
                Image(decorative: shown, scale: 1).resizable().scaledToFit()
            }
            Button("Generate") {
                Task {
                    let result = try await session.generate(prompt: "A lighthouse at sunset")
                    image = result.images.first
                }
            }
            .disabled(session.isGenerating)
        }
        .task { await session.connect() }
    }
}
```

One generation runs at a time; a second ``DrawThingsSession/generate(_:)`` while one is running
throws ``DrawThingsSession/SessionError/busy``. Cancel with ``DrawThingsSession/cancel()``.
