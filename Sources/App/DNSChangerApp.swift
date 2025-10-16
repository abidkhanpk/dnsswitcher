import SwiftUI
import AppKit

@main
struct DNSChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Use custom preferences window wiring via AppDelegate for LSUIElement menu bar app
        Settings { EmptyView() }
    }
}

struct PreferencesView: View {
    @AppStorage("customProfiles") private var customProfilesData: Data = Data()

    @State private var profiles: [DNSProfile] = []
    @State private var newName: String = ""
    @State private var newServers: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DNS Profiles").font(.headline)
            List {
                ForEach(profiles) { profile in
                    VStack(alignment: .leading) {
                        Text(profile.name).font(.subheadline).bold()
                        Text(profile.servers.joined(separator: ", ")).font(.caption)
                    }
                }.onDelete { indexSet in
                    profiles.remove(atOffsets: indexSet)
                    save()
                }
            }.frame(minHeight: 240)

            HStack {
                TextField("Profile name", text: $newName)
                TextField("Comma-separated servers", text: $newServers)
                Button("Add") {
                    let ss = newServers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    guard !newName.isEmpty, !ss.isEmpty else { return }
                    profiles.append(DNSProfile(name: newName, servers: ss))
                    newName = ""
                    newServers = ""
                    save()
                }
            }
            Spacer()
        }
        .padding(16)
        .onAppear(perform: load)
    }

    private func load() {
        if let defaults = DNSProfile.loadDefaultProfiles() {
            var merged = defaults
            if let custom = try? JSONDecoder().decode([DNSProfile].self, from: customProfilesData), !custom.isEmpty {
                merged.append(contentsOf: custom)
            }
            profiles = merged
        } else {
            if let custom = try? JSONDecoder().decode([DNSProfile].self, from: customProfilesData) {
                profiles = custom
            }
        }
    }

    private func save() {
        // Save only custom profiles (not defaults)
        if let defaults = DNSProfile.loadDefaultProfiles() {
            let custom = profiles.filter { p in !defaults.contains(where: { $0.name == p.name && $0.servers == p.servers }) }
            if let data = try? JSONEncoder().encode(custom) {
                customProfilesData = data
            }
        } else {
            if let data = try? JSONEncoder().encode(profiles) {
                customProfilesData = data
            }
        }
        NotificationCenter.default.post(name: .profilesUpdated, object: nil)
    }
}

extension Notification.Name {
    static let profilesUpdated = Notification.Name("DNSChangerProfilesUpdated")
}
