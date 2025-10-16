import Foundation
import Darwin

final class DNSChangerHelper: NSObject, DNSChangerHelperProtocol, DNSChangerHelperBlessProtocol {

    func isHelperReady(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func applyDNS(_ servers: [String], withReply reply: @escaping (Bool, String) -> Void) {
        let services = listNetworkServices()
        guard !services.isEmpty else {
            reply(false, "No network services found")
            return
        }
        let resolved = normalizeServers(servers)
        guard !resolved.isEmpty else {
            reply(false, "No valid DNS servers after normalization")
            return
        }
        for svc in services {
            let res = runCommand("/usr/sbin/networksetup", ["-setdnsservers", svc] + resolved)
            if !res.success { reply(false, "Failed for \(svc): \(res.output)"); return }
        }
        // Verify active DNS via scutil --dns
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
            let ok = resolved.contains(where: { active.contains($0) })
            reply(ok, ok ? "Applied to \(services.count) services (active: \(active.joined(separator: ", ")))" : "Applied but not active; current: \(active.joined(separator: ", "))")
        } else {
            reply(true, "Applied to \(services.count) services (could not verify)")
        }
    }

    func clearDNS(withReply reply: @escaping (Bool, String) -> Void) {
        let services = listNetworkServices()
        guard !services.isEmpty else {
            reply(false, "No network services found")
            return
        }
        for svc in services {
            let res = runCommand("/usr/sbin/networksetup", ["-setdnsservers", svc, "Empty"])
            if !res.success { reply(false, "Failed for \(svc): \(res.output)"); return }
        }
        reply(true, "Cleared on \(services.count) services")
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
    
    private func extractHostname(from s: String) -> String? {
    if let comp = URLComponents(string: s), let host = comp.host, !host.isEmpty {
    return host
    }
    if !isIPAddress(s), s.contains(".") {
    return s
    }
    return nil
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
    if !results.contains(ip) {
    results.append(ip)
    }
    }
    }
    }
    ptr = ai.ai_next
    }
    freeaddrinfo(first)
    }
    return results
    }
    
    private func normalizeServers(_ servers: [String]) -> [String] {
        var ips: [String] = []
        for raw in servers {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isIPAddress(s), !ips.contains(s) {
                ips.append(s)
            }
        }
        return ips
    }
    
    private func runCommand(_ launchPath: String, _ arguments: [String]) -> (success: Bool, output: String) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (false, "Failed to run: \(error)")
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus == 0, out)
    }
}
