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

    @State private var defaultProfiles: [DNSProfile] = []
    @State private var profiles: [DNSProfile] = [] // custom profiles only
    @AppStorage("hiddenDefaultProfileIDs") private var hiddenDefaultIDsData: Data = Data()
    @State private var hiddenDefaultIDs: Set<UUID> = []
    @State private var newName: String = ""
    @State private var newServers: String = ""
    @State private var editingProfile: DNSProfile? = nil
    @State private var editName: String = ""
    @State private var editServers: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DNS Profiles").font(.headline)
            List {
                if !defaultProfiles.isEmpty {
                    Section("Default Profiles") {
                        ForEach(defaultProfiles.filter { !hiddenDefaultIDs.contains($0.id) }) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name).font(.subheadline).bold()
                                    Text(profile.servers.joined(separator: ", ")).font(.caption)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    hiddenDefaultIDs.insert(profile.id)
                                    persistHiddenDefaults()
                                    // If active profile was hidden, clear selection
                                    if UserDefaults.standard.string(forKey: "activeProfileName") == profile.name {
                                        UserDefaults.standard.removeObject(forKey: "activeProfileName")
                                        NotificationCenter.default.post(name: .profilesUpdated, object: nil)
                                    }
                                } label: { Text("Delete") }
                            }
                        }
                    }
                }
                Section("Custom Profiles") {
                    ForEach(profiles) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name).font(.subheadline).bold()
                                Text(profile.servers.joined(separator: ", ")).font(.caption)
                            }
                            Spacer()
                            Button("Edit") {
                                editingProfile = profile
                                editName = profile.name
                                editServers = profile.servers.joined(separator: ", ")
                            }
                            .buttonStyle(LinkButtonStyle())
                            Button(role: .destructive) { deleteCustom(profile) } label: { Text("Delete") }
                        }
                    }
                    .onDelete { indexSet in
                        profiles.remove(atOffsets: indexSet)
                        save()
                    }
                }
            }.frame(minHeight: 240)

            if let editing = editingProfile {
                Divider()
                Text("Edit Profile").font(.headline)
                HStack {
                    TextField("Profile name", text: $editName)
                    TextField("Comma-separated servers", text: $editServers)
                    Button("Save") {
                        let ss = editServers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        guard !editName.isEmpty, !ss.isEmpty else { return }
                        if let idx = profiles.firstIndex(where: { $0.id == editing.id }) {
                            profiles[idx].name = editName
                            profiles[idx].servers = ss
                            save()
                        }
                        editingProfile = nil
                        editName = ""
                        editServers = ""
                    }
                    Button("Cancel") {
                        editingProfile = nil
                        editName = ""
                        editServers = ""
                    }
                }
            }

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
        defaultProfiles = DNSProfile.loadDefaultProfiles() ?? []
        if let custom = try? JSONDecoder().decode([DNSProfile].self, from: customProfilesData) {
            profiles = custom
        } else {
            profiles = []
        }
        if let data = try? JSONDecoder().decode([UUID].self, from: hiddenDefaultIDsData) {
            hiddenDefaultIDs = Set(data)
        } else {
            hiddenDefaultIDs = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            customProfilesData = data
        }
        NotificationCenter.default.post(name: .profilesUpdated, object: nil)
    }

    private func persistHiddenDefaults() {
        let arr = Array(hiddenDefaultIDs)
        if let data = try? JSONEncoder().encode(arr) {
            hiddenDefaultIDsData = data
        }
        NotificationCenter.default.post(name: .profilesUpdated, object: nil)
    }

    private func deleteCustom(_ profile: DNSProfile) {
        profiles.removeAll { $0.id == profile.id }
        // If active profile was deleted, clear selection
        if UserDefaults.standard.string(forKey: "activeProfileName") == profile.name {
            UserDefaults.standard.removeObject(forKey: "activeProfileName")
        }
        save()
    }
}

extension Notification.Name {
    static let profilesUpdated = Notification.Name("DNSChangerProfilesUpdated")
}
