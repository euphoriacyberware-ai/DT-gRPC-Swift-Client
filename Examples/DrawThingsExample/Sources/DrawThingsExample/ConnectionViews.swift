import DrawThingsKit
import SwiftUI

/// Saved servers: connect, edit, add and delete. Rebuilds DrawThingsKit 2.2's
/// `ServerProfilesView` on `ConnectionManager`.
struct ServerProfilesView: View {
    @Environment(AppModel.self) private var model
    @Environment(ConnectionManager.self) private var connection
    @State private var editing: ServerProfile?

    var body: some View {
        List {
            Section {
                ConnectionStatusView()
            }
            Section("Servers") {
                ForEach(connection.profiles) { profile in
                    ServerProfileRow(profile: profile, isActive: connection.activeProfile?.id == profile.id)
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await model.connect(to: profile) } }
                        .contextMenu {
                            Button("Edit") { editing = profile }
                            Button("Make Default") { connection.setDefault(profile) }
                            Button("Delete", role: .destructive) { connection.deleteProfile(profile) }
                        }
                }
                .onDelete { offsets in
                    offsets.map { connection.profiles[$0] }.forEach(connection.deleteProfile)
                }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            Button("Add Server", systemImage: "plus") {
                editing = ServerProfile(name: "New Server")
            }
        }
        .sheet(item: $editing) { profile in
            ServerProfileEditor(profile: profile)
        }
    }
}

struct ServerProfileRow: View {
    let profile: ServerProfile
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Text(profile.name).font(.headline)
                    if profile.isDefault {
                        Text("Default").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(profile.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if profile.useTLS { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
            if isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
        }
    }
}

/// Connection state, the server's model counts, and a hint when the shared secret is wrong.
struct ConnectionStatusView: View {
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ConnectionStatusBadge(state: connection.connectionState)
                Text(connection.activeProfile?.name ?? "No server")
            }
            if connection.connectionState.isConnected {
                Text(connection.modelsManager.summary).font(.caption).foregroundStyle(.secondary)
            }
            if let message = connection.connectionState.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if connection.serverRequiresSharedSecret {
                Text("This server needs a shared secret. Edit the profile to add it.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct ConnectionStatusBadge: View {
    let state: ConnectionState

    var body: some View {
        switch state {
        case .connected: Label("Connected", systemImage: "circle.fill").foregroundStyle(.green)
        case .connecting: Label { Text("Connecting") } icon: { ProgressView().controlSize(.small) }
        case .disconnected: Label("Disconnected", systemImage: "circle").foregroundStyle(.secondary)
        case .error: Label("Error", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}

struct ServerProfileEditor: View {
    @Environment(ConnectionManager.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State var profile: ServerProfile
    @State private var secret = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $profile.name)
                TextField("Host", text: $profile.host)
                    .autocorrectionDisabled()
                TextField("Port", value: $profile.port, format: .number.grouping(.never))
                Toggle("TLS", isOn: $profile.useTLS)
                SecureField("Shared secret", text: $secret)
                Toggle("Default server", isOn: $profile.isDefault)
            }
            .formStyle(.grouped)
            .navigationTitle(profile.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.sharedSecret = secret.isEmpty ? nil : secret
                        if connection.profiles.contains(where: { $0.id == profile.id }) {
                            connection.updateProfile(profile)
                        } else {
                            connection.addProfile(profile)
                        }
                        dismiss()
                    }
                    .disabled(profile.host.isEmpty)
                }
            }
            .onAppear { secret = profile.sharedSecret ?? "" }
        }
    }
}
