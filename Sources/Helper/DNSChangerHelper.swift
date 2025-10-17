import Foundation
import Darwin
import SystemConfiguration

final class DNSChangerHelper: NSObject, DNSChangerHelperProtocol, DNSChangerHelperBlessProtocol {

    private let dohProfileIdentifier = "com.pacman.DNSChanger.encrypteddns"
    private let dohProfileDisplayName = "DNSChanger Encrypted DNS"

    func isHelperReady(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func applyDNS(_ servers: [String], withReply reply: @escaping (Bool, String) -> Void) {
        let services = listNetworkServices()
        guard !services.isEmpty else {
            reply(false, "No network services found")
            return
        }
        let (ipServers, dohURLs, dotHosts) = classifyServers(servers)

        if let doh = dohURLs.first {
            // Remove any existing encrypted DNS profiles first
            removeAllManagedDNSProfiles()
            
            // Install the DoH profile
            let (ok, msg) = installDoHProfile(serverURL: doh)
            if !ok {
                reply(false, "Failed to install DoH profile: \(msg)")
                return
            }
            
            // DO NOT clear per-service DNS - instead set bootstrap IPs
            if let host = URLComponents(string: doh)?.host {
                let bootstrapIPs = resolveHostToIPs(host)
                if !bootstrapIPs.isEmpty {
                    // Set bootstrap IPs on all services so the DoH server can be reached
                    let (okSet, _) = setDNSServersUsingSC(bootstrapIPs)
                    if okSet {
                        // Flush caches
                        _ = runCommand("/usr/bin/dscacheutil", ["-flushcache"])
                        _ = runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
                        // Give it a moment to apply
                        Thread.sleep(forTimeInterval: 1.0)
                    }
                }
            }
            
            reply(true, "DoH profile installed: \(doh)")
            return
        }
        
        if let dot = dotHosts.first {
            // Remove any existing encrypted DNS profiles first
            removeAllManagedDNSProfiles()
            
            // Install the DoT profile
            let (ok, msg) = installDoTProfile(serverName: dot)
            if !ok {
                reply(false, "Failed to install DoT profile: \(msg)")
                return
            }
            
            // Set bootstrap IPs
            let bootstrapIPs = resolveHostToIPs(dot)
            if !bootstrapIPs.isEmpty {
                let (okSet, _) = setDNSServersUsingSC(bootstrapIPs)
                if okSet {
                    _ = runCommand("/usr/bin/dscacheutil", ["-flushcache"])
                    _ = runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
                    Thread.sleep(forTimeInterval: 1.0)
                }
            }
            
            reply(true, "DoT profile installed: \(dot)")
            return
        }
        
        if !ipServers.isEmpty {
            removeAllManagedDNSProfiles()
            let (okSet, msgSet) = setDNSServersUsingSC(ipServers)
            if !okSet { reply(false, "Failed to set DNS: \(msgSet)"); return }
            _ = runCommand("/usr/bin/dscacheutil", ["-flushcache"])
            _ = runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
            let scutil = runCommand("/usr/sbin/scutil", ["--dns"])
            if scutil.success {
                let active = scutil.output
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("nameserver[") }
                    .compactMap { line -> String? in
                        guard let part = line.split(separator: ":").dropFirst().first else { return nil }
                        return part.trimmingCharacters(in: .whitespaces)
                    }
                let ok = ipServers.contains(where: { active.contains($0) })
                reply(ok, ok ? "Applied system-wide (active: \(active.joined(separator: ", ")))" : "Applied but not active; current: \(active.joined(separator: ", "))")
            } else {
                reply(true, "Applied system-wide (could not verify)")
            }
            return
        }
        reply(false, "No valid IP or DoH/DoT servers to apply")
    }

    func clearDNS(withReply reply: @escaping (Bool, String) -> Void) {
        let (okClr, msgClr) = clearDNSServersUsingSC()
        if !okClr { reply(false, "Failed to clear DNS: \(msgClr)"); return }
        removeAllManagedDNSProfiles()
        _ = runCommand("/usr/bin/dscacheutil", ["-flushcache"])
        _ = runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        reply(true, "Cleared system-wide and removed encrypted DNS (if any)")
    }

    func flushDNSCache(withReply reply: @escaping (Bool, String) -> Void) {
        let a = runCommand("/usr/bin/dscacheutil", ["-flushcache"])
        let b = runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        if a.success && b.success { reply(true, "Flushed cache") }
        else { reply(false, "Flush error: \(a.output) | \(b.output)") }
    }

    private func listNetworkServices() -> [String] {
        let res = runCommand("/usr/sbin/networksetup", ["-listallnetworkservices"])
        guard res.success else { return [] }
        return res.output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    private func isIPAddress(_ s: String) -> Bool {
        let ipv4Pattern = "^((25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)(\\.|$)){4}$"
        let ipv6Pattern = "^[0-9a-fA-F:]+$"
        return s.range(of: ipv4Pattern, options: .regularExpression) != nil || s.range(of: ipv6Pattern, options: .regularExpression) != nil
    }

    private func resolveHostToIPs(_ host: String) -> [String] {
        var results: [String] = []
        var hints = addrinfo(ai_flags: AI_DEFAULT, ai_family: AF_UNSPEC, ai_socktype: SOCK_DGRAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &res)
        if status == 0, let first = res {
            var ptr: UnsafeMutablePointer<addrinfo>? = first
            while let ai = ptr?.pointee {
                if let sa = ai.ai_addr {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let fam = sa.pointee.sa_family
                    if fam == sa_family_t(AF_INET) || fam == sa_family_t(AF_INET6) {
                        let err = getnameinfo(sa, socklen_t(ai.ai_addrlen), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
                        if err == 0 {
                            let ip = String(cString: buffer)
                            if !results.contains(ip) { results.append(ip) }
                        }
                    }
                }
                ptr = ai.ai_next
            }
            freeaddrinfo(first)
        }
        return results
    }

    private func classifyServers(_ servers: [String]) -> (ips: [String], doh: [String], dot: [String]) {
        var ips: [String] = []
        var doh: [String] = []
        var dot: [String] = []
        for raw in servers {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isIPAddress(s) {
                if !ips.contains(s) { ips.append(s) }
                continue
            }
            if s.lowercased().hasPrefix("https://") {
                if !doh.contains(s) { doh.append(s) }
                continue
            }
            if s.lowercased().hasPrefix("tls://") {
                let host = String(s.dropFirst("tls://".count))
                if !dot.contains(host) { dot.append(host) }
                continue
            }
        }
        return (ips, doh, dot)
    }

    private func installDoHProfile(serverURL: String) -> (Bool, String) {
        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        
        // Resolve bootstrap IPs
        var bootstrap: [String] = []
        if let host = URLComponents(string: serverURL)?.host {
            bootstrap = resolveHostToIPs(host)
        }
        
        // Build ServerAddresses XML if we have bootstrap IPs
        var serverAddressesXML = ""
        if !bootstrap.isEmpty {
            serverAddressesXML = """
        <key>ServerAddresses</key>
        <array>

"""
            for ip in bootstrap {
                serverAddressesXML += "          <string>\(ip)</string>\n"
            }
            serverAddressesXML += "        </array>\n"
        }
        
        let profile = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key>
        <string>HTTPS</string>
        <key>ServerURL</key>
        <string>\(serverURL)</string>
\(serverAddressesXML)      </dict>
      <key>PayloadDisplayName</key>
      <string>\(dohProfileDisplayName)</string>
      <key>PayloadIdentifier</key>
      <string>\(dohProfileIdentifier).settings</string>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadUUID</key>
      <string>\(uuid1)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>\(dohProfileDisplayName)</string>
  <key>PayloadIdentifier</key>
  <string>\(dohProfileIdentifier)</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>\(uuid2)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadScope</key>
  <string>System</string>
</dict>
</plist>
"""
        let path = "/tmp/dnschanger_encrypted_dns.mobileconfig"
        do {
            try profile.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            return (false, "Failed to write profile: \(error)")
        }
        
        let result = runCommand("/usr/bin/profiles", ["install", "-path", path])
        if !result.success {
            return (false, "Profile install failed: \(result.output)")
        }
        
        return (true, "Profile installed successfully")
    }

    private func installDoTProfile(serverName: String) -> (Bool, String) {
        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        
        // Resolve bootstrap IPs
        let bootstrap = resolveHostToIPs(serverName)
        
        // Build ServerAddresses XML if we have bootstrap IPs
        var serverAddressesXML = ""
        if !bootstrap.isEmpty {
            serverAddressesXML = """
        <key>ServerAddresses</key>
        <array>

"""
            for ip in bootstrap {
                serverAddressesXML += "          <string>\(ip)</string>\n"
            }
            serverAddressesXML += "        </array>\n"
        }
        
        let profile = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key>
        <string>TLS</string>
        <key>ServerName</key>
        <string>\(serverName)</string>
\(serverAddressesXML)      </dict>
      <key>PayloadDisplayName</key>
      <string>\(dohProfileDisplayName)</string>
      <key>PayloadIdentifier</key>
      <string>\(dohProfileIdentifier).settings</string>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadUUID</key>
      <string>\(uuid1)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>\(dohProfileDisplayName)</string>
  <key>PayloadIdentifier</key>
  <string>\(dohProfileIdentifier)</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>\(uuid2)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadScope</key>
  <string>System</string>
</dict>
</plist>
"""
        let path = "/tmp/dnschanger_encrypted_dns.mobileconfig"
        do {
            try profile.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            return (false, "Failed to write profile: \(error)")
        }
        
        let result = runCommand("/usr/bin/profiles", ["install", "-path", path])
        if !result.success {
            return (false, "Profile install failed: \(result.output)")
        }
        
        return (true, "Profile installed successfully")
    }

    private func listManagedDNSProfileIdentifiers() -> [String] {
        let res = runCommand("/usr/bin/profiles", ["show", "-type", "configuration"])
        guard res.success else { return [] }
        var ids: [String] = []
        var currentID: String? = nil
        for raw in res.output.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("profile identifier:") {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { currentID = parts[1] }
                continue
            }
            if line.contains("com.apple.dnsSettings.managed") {
                if let id = currentID, !ids.contains(id) { ids.append(id) }
            }
        }
        return ids
    }

    private func removeAllManagedDNSProfiles() {
        let ids = listManagedDNSProfileIdentifiers()
        for id in ids {
            _ = runCommand("/usr/bin/profiles", ["remove", "-identifier", id])
        }
    }

    private func runCommand(_ launchPath: String, _ arguments: [String]) -> (success: Bool, output: String) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (false, "Failed to run: \(error)") }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus == 0, out)
    }

    private func withSCPreferences(_ body: (SCPreferences) -> Bool) -> (Bool, String) {
        guard let prefs = SCPreferencesCreate(nil, "com.pacman.DNSChanger" as CFString, nil) else {
            return (false, "SCPreferencesCreate failed")
        }
        let ok = body(prefs)
        if !ok { return (false, "No DNS services updated") }
        if !SCPreferencesCommitChanges(prefs) { return (false, "SCPreferencesCommitChanges failed") }
        if !SCPreferencesApplyChanges(prefs) { return (false, "SCPreferencesApplyChanges failed") }
        return (true, "")
    }

    private func setDNSServersUsingSC(_ addresses: [String]) -> (Bool, String) {
        return withSCPreferences { prefs in
            guard let set = SCNetworkSetCopyCurrent(prefs) else { return false }
            guard let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return false }
            var touched = false
            for svc in services {
                if let proto = SCNetworkServiceCopyProtocol(svc, kSCNetworkProtocolTypeDNS) {
                    var cfg: [String: Any] = [:]
                    cfg[kSCPropNetDNSServerAddresses as String] = addresses
                    if SCNetworkProtocolSetConfiguration(proto, cfg as CFDictionary) { touched = true }
                }
            }
            return touched
        }
    }

    private func clearDNSServersUsingSC() -> (Bool, String) {
        return withSCPreferences { prefs in
            guard let set = SCNetworkSetCopyCurrent(prefs) else { return false }
            guard let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return false }
            var touched = false
            for svc in services {
                if let proto = SCNetworkServiceCopyProtocol(svc, kSCNetworkProtocolTypeDNS) {
                    let empty: [String: Any] = [:]
                    if SCNetworkProtocolSetConfiguration(proto, empty as CFDictionary) { touched = true }
                }
            }
            return touched
        }
    }
}
