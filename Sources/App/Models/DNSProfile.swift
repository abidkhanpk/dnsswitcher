import Foundation

struct DNSProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var servers: [String]

    init(id: UUID = UUID(), name: String, servers: [String]) {
        self.id = id
        self.name = name
        self.servers = servers
    }
}

extension DNSProfile {
    static func loadDefaultProfiles() -> [DNSProfile]? {
        // Try exact expected location under config/
        if let url = Bundle.main.url(forResource: "default_profiles", withExtension: "json", subdirectory: "config") {
            if let profiles = tryLoad(url) { return profiles }
        }
        // Try flat resource
        if let url = Bundle.main.url(forResource: "default_profiles", withExtension: "json") {
            if let profiles = tryLoad(url) { return profiles }
        }
        // Search recursively for the file in the bundle
        if let resourcePath = Bundle.main.resourcePath {
            let fm = FileManager.default
            if let enumerator = fm.enumerator(at: URL(fileURLWithPath: resourcePath), includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent == "default_profiles.json" {
                        if let profiles = tryLoad(fileURL) { return profiles }
                    }
                }
            }
        }
        // Built-in fallback (ensures profiles are available even if resource isn't bundled)
        return builtInDefaults
    }

    private static func tryLoad(_ url: URL) -> [DNSProfile]? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([DNSProfile].self, from: data)
        } catch {
            NSLog("DNSChanger: Failed to load default profiles at \(url.path): \(error)")
            return nil
        }
    }

    private static var builtInDefaults: [DNSProfile] {
        return [
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Cloudflare", servers: [
                "1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Google", servers: [
                "8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Quad9", servers: [
                "9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "OpenDNS", servers: [
                "208.67.222.222", "208.67.220.220"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "AdGuard", servers: [
                "94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"
            ])
        ,
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "NextDNS", servers: [
                "45.90.28.0", "45.90.30.0", "2a07:a8c0::", "2a07:a8c1::"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, name: "CleanBrowsing (Family)", servers: [
                "185.228.168.168", "185.228.169.168", "2a0d:2a00:1::", "2a0d:2a00:2::"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, name: "Mullvad", servers: [
                "194.242.2.2", "194.242.2.3"
            ]),
            DNSProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, name: "OpenNIC (example)", servers: [
                "193.183.98.66", "172.104.136.243"
            ])
        ]
    }
}
