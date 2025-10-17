import Foundation
import ServiceManagement
import Security
import AppKit

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
        let conn = getConnection()
        let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
            self.installHelperDaemonThenCheck(completion: completion)
        } as? DNSChangerHelperXPCProtocol

        proxy?.isHelperReady(withReply: { ready in
            if ready {
                completion(true)
            } else {
                self.installHelperDaemonThenCheck(completion: completion)
            }
        })
    }

    private func blessHelper(completion: @escaping (Bool) -> Void) {
        let helperID = "com.pacman.DNSChangerHelper" as CFString

        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            NSLog("SMJobBless: AuthorizationCreate failed: \(authStatus)")
            completion(false)
            return
        }

        var okCopy = false
        withUnsafePointer(to: kSMRightBlessPrivilegedHelper) { ptr in
            var blessItem = AuthorizationItem(name: ptr.pointee, valueLength: 0, value: nil, flags: 0)
            var rights = AuthorizationRights(count: 1, items: &blessItem)
            let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
            let copyStatus = AuthorizationCopyRights(auth, &rights, nil, flags, nil)
            okCopy = (copyStatus == errAuthorizationSuccess)
            if !okCopy {
                NSLog("SMJobBless: AuthorizationCopyRights failed: \(copyStatus)")
            }
        }
        guard okCopy else { completion(false); return }

        var cfError: Unmanaged<CFError>?
        let ok = SMJobBless(kSMDomainSystemLaunchd, helperID, auth, &cfError)
        if !ok {
            if let err = cfError?.takeRetainedValue() { NSLog("SMJobBless failed: \(err)") }
            completion(false)
        } else {
            completion(true)
        }
    }

    func applyDNS(servers: [String], completion: @escaping (Bool, String) -> Void) {
        ensureHelperBlessed { _ in
            if let proxy = self.getConnection().remoteObjectProxyWithErrorHandler({ _ in
                self.applyDNSViaAdmin(servers: servers, completion: completion)
            }) as? DNSChangerHelperXPCProtocol {
                proxy.applyDNS(servers, withReply: completion)
            } else {
                self.applyDNSViaAdmin(servers: servers, completion: completion)
            }
        }
    }

    func clearDNS(completion: @escaping (Bool, String) -> Void) {
        ensureHelperBlessed { _ in
            if let proxy = self.getConnection().remoteObjectProxyWithErrorHandler({ _ in
                self.clearDNSViaAdmin(completion: completion)
            }) as? DNSChangerHelperXPCProtocol {
                proxy.clearDNS(withReply: completion)
            } else {
                self.clearDNSViaAdmin(completion: completion)
            }
        }
    }

    func flushDNSCache(completion: @escaping (Bool, String) -> Void) {
        ensureHelperBlessed { _ in
            if let proxy = self.getConnection().remoteObjectProxyWithErrorHandler({ _ in
                self.flushDNSViaAdmin(completion: completion)
            }) as? DNSChangerHelperXPCProtocol {
                proxy.flushDNSCache(withReply: completion)
            } else {
                self.flushDNSViaAdmin(completion: completion)
            }
        }
    }

    private func applyDNSViaAdmin(servers: [String], completion: @escaping (Bool, String) -> Void) {
        let (ipServers, dohURLs, dotHosts) = classifyServers(servers)

        if let doh = dohURLs.first {
            _ = runWithAdmin(args: ["/bin/sh", "-c", "/usr/bin/profiles show -type configuration 2>/dev/null | /usr/bin/awk '/Profile identifier:/ {id=$3} /com.apple.dnsSettings.managed/ {if (id) print id}' | while read -r id; do /usr/bin/profiles remove -identifier \"$id\" || true; /usr/bin/profiles -R -p \"$id\" || true; done"])            
            let (ok, message) = installDoHProfileViaAdmin(serverURL: doh)
            if ok {
                let services = listNetworkServices()
                var lines: [String] = []
                for svc in services {
                    let svcQ = shellEscape(svc)
                    lines.append("/usr/sbin/networksetup -setdnsservers \(svcQ) Empty")
                }
                lines.append("/usr/bin/dscacheutil -flushcache")
                lines.append("/usr/bin/killall -HUP mDNSResponder")
                _ = runWithAdmin(args: ["/bin/sh", "-c", lines.joined(separator: "\n")])
            }
            completion(ok, message)
            return
        }

        if let dot = dotHosts.first {
            _ = runWithAdmin(args: ["/bin/sh", "-c", "/usr/bin/profiles show -type configuration 2>/dev/null | /usr/bin/awk '/Profile identifier:/ {id=$3} /com.apple.dnsSettings.managed/ {if (id) print id}' | while read -r id; do /usr/bin/profiles remove -identifier \"$id\" || true; /usr/bin/profiles -R -p \"$id\" || true; done"])            
            let (ok, message) = installDoTProfileViaAdmin(serverName: dot)
            if ok {
                let services = listNetworkServices()
                var lines: [String] = []
                for svc in services {
                    let svcQ = shellEscape(svc)
                    lines.append("/usr/sbin/networksetup -setdnsservers \(svcQ) Empty")
                }
                lines.append("/usr/bin/dscacheutil -flushcache")
                lines.append("/usr/bin/killall -HUP mDNSResponder")
                _ = runWithAdmin(args: ["/bin/sh", "-c", lines.joined(separator: "\n")])
            }
            completion(ok, message)
            return
        }

        guard !ipServers.isEmpty else { completion(false, "No valid DNS servers to apply"); return }
        let services = listNetworkServices()
        guard !services.isEmpty else { completion(false, "No network services found"); return }

        let ipsQ = ipServers.map { shellEscape($0) }.joined(separator: " ")
        var lines: [String] = []
        lines.append("/usr/bin/profiles show -type configuration 2>/dev/null | /usr/bin/awk '/Profile identifier:/ {id=$3} /com.apple.dnsSettings.managed/ {if (id) print id}' | while read -r id; do /usr/bin/profiles remove -identifier \"$id\" || true; /usr/bin/profiles -R -p \"$id\" || true; done")
        for svc in services {
            let svcQ = shellEscape(svc)
            lines.append("/usr/sbin/networksetup -setdnsservers \(svcQ) \(ipsQ)")
        }
        lines.append("/usr/bin/dscacheutil -flushcache")
        lines.append("/usr/bin/killall -HUP mDNSResponder")
        let script = "set -e\n" + lines.joined(separator: "\n")
        let result = runWithAdmin(args: ["/bin/sh", "-c", script])

        let active = currentDNSServers()
        let ok = ipServers.contains(where: { active.contains($0) }) && result.success
        completion(ok, ok ? "Applied to \(services.count) services (active: \(active.joined(separator: ", ")))" : (result.success ? "Applied but not active; current: \(active.joined(separator: ", "))" : result.output))
    }

    private func clearDNSViaAdmin(completion: @escaping (Bool, String) -> Void) {
        let services = listNetworkServices()
        guard !services.isEmpty else { completion(false, "No network services found"); return }

        var lines: [String] = []
        for svc in services {
            let svcQ = shellEscape(svc)
            lines.append("/usr/sbin/networksetup -setdnsservers \(svcQ) Empty")
        }
        lines.append("/usr/bin/profiles show -type configuration 2>/dev/null | /usr/bin/awk '/Profile identifier:/ {id=$3} /com.apple.dnsSettings.managed/ {if (id) print id}' | while read -r id; do /usr/bin/profiles remove -identifier \"$id\" || true; /usr/bin/profiles -R -p \"$id\" || true; done")
        lines.append("/usr/bin/dscacheutil -flushcache")
        lines.append("/usr/bin/killall -HUP mDNSResponder")
        let script = "set -e\n" + lines.joined(separator: "\n")
        let result = runWithAdmin(args: ["/bin/sh", "-c", script])
        completion(result.success, result.success ? "Cleared on \(services.count) services" : result.output)
    }

    private func flushDNSViaAdmin(completion: @escaping (Bool, String) -> Void) {
        let script = "set -e\n/usr/bin/dscacheutil -flushcache\n/usr/bin/killall -HUP mDNSResponder"
        let result = runWithAdmin(args: ["/bin/sh", "-c", script])
        completion(result.success, result.success ? "Flushed cache" : result.output)
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

    private func isIPAddress(_ s: String) -> Bool {
        let ipv4 = "^((25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)(\\.|$)){4}$"
        let ipv6 = "^[0-9a-fA-F:]+$"
        return s.range(of: ipv4, options: .regularExpression) != nil || s.range(of: ipv6, options: .regularExpression) != nil
    }

    private func currentDNSServers() -> [String] {
        let task = Process()
        task.launchPath = "/usr/sbin/scutil"
        task.arguments = ["--dns"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return [] }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        var servers: [String] = []
        out.components(separatedBy: "\n").forEach { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("nameserver[") {
                if let part = t.split(separator: ":").dropFirst().first {
                    let ip = part.trimmingCharacters(in: .whitespaces)
                    if !servers.contains(ip) { servers.append(ip) }
                }
            }
        }
        return servers
    }

    private func shellEscape(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func classifyServers(_ servers: [String]) -> (ips: [String], doh: [String], dot: [String]) {
        var ips: [String] = []
        var doh: [String] = []
        var dot: [String] = []
        for raw in servers {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isIPAddress(s) {
                if !ips.contains(s) { ips.append(s) }
            } else if s.lowercased().hasPrefix("https://") {
                if !doh.contains(s) { doh.append(s) }
            } else if s.lowercased().hasPrefix("tls://") {
                let host = String(s.dropFirst("tls://".count))
                if !dot.contains(host) { dot.append(host) }
            }
        }
        return (ips, doh, dot)
    }

    private func installDoHProfileViaAdmin(serverURL: String) -> (Bool, String) {
        let settingsUUID = UUID().uuidString
        let profileUUID = UUID().uuidString
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
        <key>SupplementalMatchDomains</key>
        <array>
          <string></string>
        </array>
      </dict>
      <key>PayloadDisplayName</key>
      <string>DNSChanger Encrypted DNS</string>
      <key>PayloadIdentifier</key>
      <string>com.pacman.DNSChanger.encrypteddns.settings</string>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadUUID</key>
      <string>\(settingsUUID)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>DNSChanger Encrypted DNS</string>
  <key>PayloadIdentifier</key>
  <string>com.pacman.DNSChanger.encrypteddns</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>\(profileUUID)</string>
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
            let result = runWithAdmin(args: ["/usr/bin/profiles", "install", "-path", path])
            return (result.success, result.output)
        } catch {
            return (false, "Failed to write profile: \(error)")
        }
    }

    private func installDoTProfileViaAdmin(serverName: String) -> (Bool, String) {
        let settingsUUID = UUID().uuidString
        let profileUUID = UUID().uuidString
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
        <key>SupplementalMatchDomains</key>
        <array>
          <string></string>
        </array>
      </dict>
      <key>PayloadDisplayName</key>
      <string>DNSChanger Encrypted DNS</string>
      <key>PayloadIdentifier</key>
      <string>com.pacman.DNSChanger.encrypteddns.settings</string>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadUUID</key>
      <string>\(settingsUUID)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>DNSChanger Encrypted DNS</string>
  <key>PayloadIdentifier</key>
  <string>com.pacman.DNSChanger.encrypteddns</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>\(profileUUID)</string>
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
            let result = runWithAdmin(args: ["/usr/bin/profiles", "install", "-path", path])
            return (result.success, result.output)
        } catch {
            return (false, "Failed to write profile: \(error)")
        }
    }

    private func installHelperDaemonThenCheck(completion: @escaping (Bool) -> Void) {
        installHelperDaemon { ok, _ in
            if ok {
                self.connection = nil
                let conn = self.getConnection()
                if let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in completion(false) }) as? DNSChangerHelperXPCProtocol {
                    proxy.isHelperReady(withReply: { ready in completion(ready) })
                } else {
                    completion(false)
                }
            } else {
                self.blessHelper(completion: completion)
            }
        }
    }

    private func installHelperDaemon(completion: @escaping (Bool, String) -> Void) {
        let bundlePath = Bundle.main.bundlePath
        let helperSrc = bundlePath + "/Contents/Library/LaunchServices/com.pacman.DNSChangerHelper"
        let fm = FileManager.default
        guard fm.fileExists(atPath: helperSrc) else {
            completion(false, "Helper binary not found at \(helperSrc)")
            return
        }
        let plist = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">

        <plist version=\"1.0\"><dict>
          <key>Label</key><string>com.pacman.DNSChangerHelper</string>
          <key>ProgramArguments</key>
          <array><string>/Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper</string></array>
          <key>MachServices</key><dict><key>com.pacman.DNSChangerHelper.mach</key><true/></dict>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>/var/log/com.pacman.DNSChangerHelper.out.log</string>
          <key>StandardErrorPath</key><string>/var/log/com.pacman.DNSChangerHelper.err.log</string>
        </dict></plist>
        """
        let tempPlist = "/tmp/com.pacman.DNSChangerHelper.plist"
        do {
            try plist.write(toFile: tempPlist, atomically: true, encoding: .utf8)
        } catch {
            completion(false, "Failed to write temp plist: \(error)")
            return
        }
        let lines: [String] = [
            "set -e",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp -f \(shellEscape(helperSrc)) /Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper",
            "/usr/sbin/chown root:wheel /Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper",
            "/bin/chmod 755 /Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper",
            "/usr/bin/xattr -dr com.apple.quarantine /Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper || true",
            "/bin/mv -f \(shellEscape(tempPlist)) /Library/LaunchDaemons/com.pacman.DNSChangerHelper.plist",
            "/usr/sbin/chown root:wheel /Library/LaunchDaemons/com.pacman.DNSChangerHelper.plist",
            "/bin/chmod 644 /Library/LaunchDaemons/com.pacman.DNSChangerHelper.plist",
            "/bin/launchctl bootout system/com.pacman.DNSChangerHelper >/dev/null 2>&1 || true",
            "/bin/launchctl bootstrap system /Library/LaunchDaemons/com.pacman.DNSChangerHelper.plist",
            "/bin/launchctl kickstart -k system/com.pacman.DNSChangerHelper"
        ]
        let script = lines.joined(separator: "\n")
        let result = runWithAdmin(args: ["/bin/sh", "-c", script])
        completion(result.success, result.output)
    }
}
