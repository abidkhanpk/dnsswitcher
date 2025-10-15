import Foundation

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
        for svc in services {
            let res = runCommand("/usr/sbin/networksetup", ["-setdnsservers", svc,] + servers)
            if !res.success { reply(false, "Failed for \(svc): \(res.output)"); return }
        }
        reply(true, "Applied to \(services.count) services")
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
