import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: DNSChangerHelperXPCProtocol.self)
        newConnection.exportedObject = DNSChangerHelper()
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: "com.pacman.DNSChangerHelper.mach")
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
