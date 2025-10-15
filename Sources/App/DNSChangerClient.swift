import Foundation
import ServiceManagement

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
        var cfError: Unmanaged<CFError>?
        let helperID = "com.pacman.DNSChangerHelper"
        let blessed = SMJobBless(kSMDomainSystemLaunchd, helperID as CFString, nil, &cfError)
        if !blessed {
            if let err = cfError?.takeRetainedValue() { NSLog("SMJobBless failed: \(err)") }
            completion(false)
        } else {
            completion(true)
        }
    }

    func applyDNS(servers: [String], completion: @escaping (Bool, String) -> Void) {
        let proxy = getConnection().remoteObjectProxyWithErrorHandler { error in
            completion(false, "Connection error: \(error.localizedDescription)")
        } as? DNSChangerHelperXPCProtocol
        proxy?.applyDNS(servers, withReply: completion)
    }

    func clearDNS(completion: @escaping (Bool, String) -> Void) {
        let proxy = getConnection().remoteObjectProxyWithErrorHandler { error in
            completion(false, "Connection error: \(error.localizedDescription)")
        } as? DNSChangerHelperXPCProtocol
        proxy?.clearDNS(withReply: completion)
    }

    func flushDNSCache(completion: @escaping (Bool, String) -> Void) {
        let proxy = getConnection().remoteObjectProxyWithErrorHandler { error in
            completion(false, "Connection error: \(error.localizedDescription)")
        } as? DNSChangerHelperXPCProtocol
        proxy?.flushDNSCache(withReply: completion)
    }
}
