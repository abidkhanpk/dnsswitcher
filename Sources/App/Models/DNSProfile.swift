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
        if let url = Bundle.main.url(forResource: "default_profiles", withExtension: "json", subdirectory: "config") {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([DNSProfile].self, from: data)
            } catch {
                NSLog("DNSChanger: Failed to load default profiles: \(error)")
            }
        }
        return nil
    }
}
