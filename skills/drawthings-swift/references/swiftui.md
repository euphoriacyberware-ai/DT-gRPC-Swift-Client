# Building SwiftUI views on DrawThings-Swift

The library has no views. Its state types are `@Observable`, so:

| Old ObservableObject style | Use |
|---|---|
| `@StateObject var x = X()` | `@State private var x = X()` |
| `@ObservedObject var x: X` | `let x: X` (or `@Bindable var x: X` for bindings) |
| `.environmentObject(x)` / `@EnvironmentObject` | `.environment(x)` / `@Environment(X.self) private var x` |

Display `CGImage` results and previews with `Image(decorative: cgImage, scale: 1)`.

## Patterns

```swift
// Queue list with progress, reordering and cancel.
struct QueueList: View {
    let queue: GenerationQueue
    var body: some View {
        List {
            if let job = queue.current {
                ProgressView(value: queue.progress?.fractionCompleted ?? 0) {
                    Text(queue.progress?.stage.description ?? job.name)
                }
                if let preview = queue.preview { Image(decorative: preview, scale: 1).resizable().scaledToFit() }
            }
            ForEach(queue.pending) { Text($0.name) }
                .onMove { queue.movePending(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in offsets.map { queue.pending[$0].id }.forEach { queue.cancel($0) } }
            ForEach(queue.finished.reversed()) { job in
                if let image = job.result?.images.first { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            }
        }
    }
}

// Bindings into an observable from the environment.
struct PromptField: View {
    @Environment(ConfigurationManager.self) private var configuration
    var body: some View {
        @Bindable var configuration = configuration
        TextField("Prompt", text: $configuration.prompt)
    }
}
```

`Examples/DrawThingsExample` in the package is a complete app (generate, queue, video, server
profiles) to copy patterns from.

## A Swift-package SwiftUI app on macOS

A SwiftUI `App` built as a Swift package executable (`swift run`, or running a package scheme in
Xcode) has no bundle, so macOS starts it as a background process: no Dock icon and its window stays
behind other apps. Add an app delegate that makes it regular (an Xcode app target doesn't need this):

```swift
#if os(macOS)
import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
#endif
// In the App: #if os(macOS) @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate #endif
```
