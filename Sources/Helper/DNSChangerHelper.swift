import Foundation
import Darwin
import SystemConfiguration

final class DNSChangerHelper: NSObject, DNSChangerHelperProtocol, DNSChangerHelperBlessProtocol {

    private let proxyManager = ProxyManager.shared

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

        // Handle DoH
        if let doh = dohURLs.first {
            // Start the proxy with DoH
            proxyManager.startProxy(serverURL: doh) { success, message in
                if !success {
                    reply(false, "Failed to start DoH proxy: \(message)")
                    return
                }
                
                // Set system DNS to point to the proxy
                let proxyIP = self.proxyManager.getProxyDNSAddress()
                let (okSet, msgSet) = self.setDNSServersUsingSC([proxyIP])
                if !okSet {
                    self.proxyManager.stopProxy()
                    reply(false, "Failed to set DNS to proxy: \(msgSet)")
                    return
                }
                
                // Flush caches
                _ = self.runCommand("/usr/bin/dscacheutil", ["-flushcache"])
                _ = self.runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
                
                reply(true, "DoH active via local proxy: \(doh)")
            }
            return
        }
        
        // Handle DoT
        if let dot = dotHosts.first {
            let dotURL = "tls://\(dot)"
            proxyManager.startProxy(serverURL: dotURL) { success, message in
                if !success {
                    reply(false, "Failed to start DoT proxy: \(message)")
                    return
                }
                
                // Set system DNS to point to the proxy
                let proxyIP = self.proxyManager.getProxyDNSAddress()
                let (okSet, msgSet) = self.setDNSServersUsingSC([proxyIP])
                if !okSet {
                    self.proxyManager.stopProxy()
                    reply(false, "Failed to set DNS to proxy: \(msgSet)")
                    return
                }
                
                // Flush caches
                _ = self.runCommand("/usr/bin/dscacheutil", ["-flushcache"])
                _ = self.runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
                
                reply(true, "DoT active via local proxy: \(dot)")
            }
            return
        }
        
        // Handle regular IP DNS
        if !ipServers.isEmpty {
            // Stop proxy if running
            proxyManager.stopProxy()
            
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
        // Stop proxy if running
        proxyManager.stopProxy()
        
        let (okClr, msgClr) = clearDNSServersUsingSC()
        if !okClr { reply(false, "Failed to clear DNS: \(msgClr)"); return }
        _ = runCommand("/usr/bin/dscacheutil", ["-flushcache"])
        _ = runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        reply(true, "Cleared system-wide and stopped proxy")
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
