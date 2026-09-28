import DrawThingsKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Generate", systemImage: "wand.and.stars") {
                NavigationStack { GenerateView() }
            }
            Tab("Queue", systemImage: "list.bullet") {
                NavigationStack {
                    if let queue = model.queue {
                        QueueView(queue: queue)
                    } else {
                        ContentUnavailableView("Not connected", systemImage: "network.slash",
                                               description: Text("Connect to a server to start the queue."))
                    }
                }
            }
            Tab("Video", systemImage: "film") {
                NavigationStack { VideoView() }
            }
            Tab("Servers", systemImage: "server.rack") {
                NavigationStack { ServerProfilesView() }
            }
        }
    }
}

/// A generated image, drawn at its pixel size.
struct ResultImage: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
    }
}
