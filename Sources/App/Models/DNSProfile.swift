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
        // Try with preserved folder structure first
        if let url = Bundle.main.url(forResource: "default_profiles", withExtension: "json", subdirectory: "config") {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([DNSProfile].self, from: data)
            } catch {
                NSLog("DNSChanger: Failed to load default profiles (config/): \(error)")
            }
        }
        // Fallback: flattened resource (no subdirectory)
        if let url = Bundle.main.url(forResource: "default_profiles", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([DNSProfile].self, from: data)
            } catch {
                NSLog("DNSChanger: Failed to load default profiles (flat): \(error)")
            }
        }
        // Last resort: search by name anywhere in bundle resources
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            if let url = urls.first(where: { $0.lastPathComponent == "default_profiles.json" }) {
                do {
                    let data = try Data(contentsOf: url)
                    return try JSONDecoder().decode([DNSProfile].self, from: data)
                } catch {
                    NSLog("DNSChanger: Failed to load default profiles (search): \(error)")
                }
            }
        }
        return nil
    }
}
