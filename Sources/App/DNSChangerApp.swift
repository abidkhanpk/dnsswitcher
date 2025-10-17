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
    @State private var quickApplyText: String = ""

    private enum ProfileKind: String, CaseIterable, Identifiable { case ip = "IP", doh = "DoH", dot = "DoT"; var id: String { rawValue } }
    @State private var newKind: ProfileKind = .ip
    @State private var editKind: ProfileKind = .ip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Apply").font(.headline)
            HStack {
                TextField("Enter IPs, DoH URL (https://...) or DoT host (tls://... or hostname)", text: $quickApplyText)
                Button("Apply Now") {
                    let servers = parseFlexible(quickApplyText)
                    guard !servers.isEmpty else { return }
                    DNSChangerClient.shared.applyDNS(servers: servers) { _, _ in }
                    quickApplyText = ""
                }
            }
            Divider().padding(.vertical, 4)
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
                    Picker("Type", selection: $editKind) {
                    ForEach(ProfileKind.allCases) { k in Text(k.rawValue).tag(k) }
                    }.pickerStyle(SegmentedPickerStyle()).frame(width: 220)
                    Button("Save") {
                    let ss = buildServers(from: editServers, kind: editKind)
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
                TextField("Servers (IPs, DoH URL, or DoT host)", text: $newServers)
                Picker("Type", selection: $newKind) {
                    ForEach(ProfileKind.allCases) { k in Text(k.rawValue).tag(k) }
                }.pickerStyle(SegmentedPickerStyle()).frame(width: 220)
                Button("Add") {
                    let ss = buildServers(from: newServers, kind: newKind)
                    guard !newName.isEmpty, !ss.isEmpty else { return }
                    profiles.append(DNSProfile(name: newName, servers: ss))
                    newName = ""
                    newServers = ""
                    newKind = .ip
                    save()
                }
            }
            Spacer()
        }
        .padding(16)
        .onAppear(perform: load)
    }

    private func load() {
        // set editKind when a profile is selected for editing
        if let p = editingProfile {
            editKind = inferKind(for: p.servers)
            editServers = p.servers.joined(separator: ", ")
        }
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
private func parseFlexible(_ text: String) -> [String] {
        var results: [String] = []
        func addToken(_ t: String) {
            var token = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return }
            if token.lowercased().hasPrefix("doh:") {
                token = "https://" + String(token.dropFirst(4))
            } else if token.lowercased().hasPrefix("dot:") {
                token = "tls://" + String(token.dropFirst(4))
            } else if !token.lowercased().hasPrefix("https://") && !token.lowercased().hasPrefix("tls://") {
                if token.contains(".") && token.range(of: "^[-A-Za-z0-9_.:]+$", options: .regularExpression) != nil {
                    token = "tls://" + token
                }
            }
            if !results.contains(token) { results.append(token) }
        }
        text.split(separator: ",").forEach { addToken(String($0)) }
        return results
    }

    private func buildServers(from text: String, kind: ProfileKind) -> [String] {
        let parts = text.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        switch kind {
        case .ip:
            return parts
        case .doh:
            guard let first = parts.first else { return [] }
            if first.lowercased().hasPrefix("https://") { return [first] }
            if first.lowercased().hasPrefix("doh:") { return ["https://" + String(first.dropFirst(4))] }
            // If bare host, try to prefix https://
            return ["https://" + first]
        case .dot:
            guard let first = parts.first else { return [] }
            if first.lowercased().hasPrefix("tls://") { return [first] }
            if first.lowercased().hasPrefix("dot:") { return ["tls://" + String(first.dropFirst(4))] }
            return ["tls://" + first]
        }
    }

    private func inferKind(for servers: [String]) -> ProfileKind {
        if let s = servers.first {
            if s.lowercased().hasPrefix("https://") { return .doh }
            if s.lowercased().hasPrefix("tls://") { return .dot }
        }
        return .ip
    }
}

extension Notification.Name {
    static let profilesUpdated = Notification.Name("DNSChangerProfilesUpdated")
}
