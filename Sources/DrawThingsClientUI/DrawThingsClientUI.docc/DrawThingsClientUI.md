# ``DrawThingsClientUI``

Observable Draw Things generation state for SwiftUI.

## Overview

``DrawThingsSession`` wraps a `DrawThingsService` and mirrors its event stream into observable
properties, so views update as progress and previews arrive:

```swift
struct ContentView: View {
    @State private var session = try! DrawThingsSession(address: "localhost:7859")

    var body: some View {
        VStack {
            if let progress = session.progress {
                ProgressView(value: progress.fractionCompleted ?? 0)
            }
            if let preview = session.preview {
                Image(decorative: preview, scale: 1)
            }
        }
        .task { await session.connect() }
    }
}
```

## Topics

- ``DrawThingsSession``
