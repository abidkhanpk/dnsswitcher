import Foundation
import ServiceManagement
import Security

final class DNSChangerClient: NSObject {
    static let shared = DNSChangerClient()

    private let helperMachName = "com.pacman.DNSChangerHelper.mach"
    private var connection: NSXPCConnection?

    private override init() {}

    private func getConnection() -> NSXPCConnection {
        if let conn = connection { return conn }
        let conn = NSXPCConnection(machServiceName: helperMachName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: DNSChangerHelperXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in self?.connection = nil }
        conn.resume()
        self.connection = conn
        return conn
    }

    func ensureHelperBlessed(completion: @escaping (Bool) -> Void) {
        // Try to ping helper; if not reachable, attempt bless
        let conn = getConnection()
        let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
            self.blessHelper(completion: completion)
        } as? DNSChangerHelperXPCProtocol

        // Attempt simple call to check readiness
        proxy?.isHelperReady(withReply: { ready in
            if ready { completion(true) } else { self.blessHelper(completion: completion) }
        })
    }

    private func blessHelper(completion: @escaping (Bool) -> Void) {
        let helperID = "com.pacman.DNSChangerHelper" as CFString

        // Create an authorization reference
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            NSLog("SMJobBless: AuthorizationCreate failed: \(authStatus)")
            completion(false)
            return
        }

        // Request the bless right; this will prompt the user
        var blessItem = AuthorizationItem(name: kSMRightBlessPrivilegedHelper, valueLength: 0, value: nil, flags: 0)
        var rights = AuthorizationRights(count: 1, items: &blessItem)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let copyStatus = AuthorizationCopyRights(auth, &rights, nil, flags, nil)
        guard copyStatus == errAuthorizationSuccess else {
            NSLog("SMJobBless: AuthorizationCopyRights failed: \(copyStatus)")
            completion(false)
            return
        }

        var cfError: Unmanaged<CFError>?
        let ok = SMJobBless(kSMDomainSystemLaunchd, helperID, auth, &cfError)
        if !ok {
            if let err = cfError?.takeRetainedValue() { NSLog("SMJobBless failed: \(err)") }
            completion(false)
        } else {
            completion(true)
        }
    }

    // MARK: - Public API (with helper fallback)

    func applyDNS(servers: [String], completion: @escaping (Bool, String) -> Void) {
        if let proxy = getConnection().remoteObjectProxyWithErrorHandler({ _ in
            self.applyDNSViaAdmin(servers: servers, completion: completion)
        }) as? DNSChangerHelperXPCProtocol {
            proxy.applyDNS(servers, withReply: completion)
        } else {
            applyDNSViaAdmin(servers: servers, completion: completion)
        }
    }

    func clearDNS(completion: @escaping (Bool, String) -> Void) {
        if let proxy = getConnection().remoteObjectProxyWithErrorHandler({ _ in
            self.clearDNSViaAdmin(completion: completion)
        }) as? DNSChangerHelperXPCProtocol {
            proxy.clearDNS(withReply: completion)
        } else {
            clearDNSViaAdmin(completion: completion)
        }
    }

    func flushDNSCache(completion: @escaping (Bool, String) -> Void) {
        if let proxy = getConnection().remoteObjectProxyWithErrorHandler({ _ in
            self.flushDNSViaAdmin(completion: completion)
        }) as? DNSChangerHelperXPCProtocol {
            proxy.flushDNSCache(withReply: completion)
        } else {
            flushDNSViaAdmin(completion: completion)
        }
    }

    // MARK: - Fallback admin operations (without helper)

    private func applyDNSViaAdmin(servers: [String], completion: @escaping (Bool, String) -> Void) {
        let services = listNetworkServices()
        guard !services.isEmpty else { completion(false, "No network services found"); return }
        var allOK = true
        var lastMsg = ""
        for svc in services {
            let args = ["/usr/sbin/networksetup", "-setdnsservers", svc] + servers
            let res = runWithAdmin(args: args)
            allOK = allOK && res.success
            lastMsg = res.output
            if !allOK { break }
        }
        completion(allOK, allOK ? "Applied to \(services.count) services" : lastMsg)
    }

    private func clearDNSViaAdmin(completion: @escaping (Bool, String) -> Void) {
        let services = listNetworkServices()
        guard !services.isEmpty else { completion(false, "No network services found"); return }
        var allOK = true
        var lastMsg = ""
        for svc in services {
            let args = ["/usr/sbin/networksetup", "-setdnsservers", svc, "Empty"]
            let res = runWithAdmin(args: args)
            allOK = allOK && res.success
            lastMsg = res.output
            if !allOK { break }
        }
        completion(allOK, allOK ? "Cleared on \(services.count) services" : lastMsg)
    }

    private func flushDNSViaAdmin(completion: @escaping (Bool, String) -> Void) {
        let a = runWithAdmin(args: ["/usr/bin/dscacheutil", "-flushcache"]) 
        let b = runWithAdmin(args: ["/usr/bin/killall", "-HUP", "mDNSResponder"]) 
        let ok = a.success && b.success
        completion(ok, ok ? "Flushed cache" : "Flush error: \(a.output) | \(b.output)")
    }

    private func listNetworkServices() -> [String] {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return [] }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    private func runWithAdmin(args: [String]) -> (success: Bool, output: String) {
        let argv = args.map { shellEscape($0) }.joined(separator: " ")
        let osaArg = "do shell script \"\(argv.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", osaArg]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (false, "Failed to run osascript: \(error)") }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus == 0, out)
    }

    private func shellEscape(_ s: String) -> String {
        if s.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\\\"$`"))) == nil {
            return s
        }
        var result = "'"
        for c in s { if c == "'" { result += "'\\''" } else { result.append(c) } }
        result += "'"
        return result
    }
}
