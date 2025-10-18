import Foundation

/// Manages the dnscrypt-proxy process for DoH/DoT support
class ProxyManager {
    static let shared = ProxyManager()
    
    private var proxyProcess: Process?
    private let proxyPort = 53535
    private let proxyAddress = "127.0.0.1"
    
    private init() {}
    
    /// Check if proxy is currently running
    var isRunning: Bool {
        return proxyProcess?.isRunning ?? false
    }
    
    /// Start the proxy with a specific DoH/DoT URL
    func startProxy(serverURL: String, completion: @escaping (Bool, String) -> Void) {
        // Stop any existing proxy
        stopProxy()
        
        // Check if DoT is requested (not supported by dnscrypt-proxy 2.1.5)
        if serverURL.lowercased().hasPrefix("tls://") {
            completion(false, "DoT is not supported by dnscrypt-proxy 2.1.5. Please use DoH instead.")
            return
        }
        
        // Get paths
        guard let proxyBinary = getProxyBinaryPath(),
              let configTemplate = getConfigTemplatePath() else {
            completion(false, "Proxy binary or config not found")
            return
        }
        
        // Remove quarantine attribute from binary
        removeQuarantine(from: proxyBinary)
        
        // Create runtime config
        let runtimeConfigPath = createRuntimeConfig(serverURL: serverURL, templatePath: configTemplate)
        guard let configPath = runtimeConfigPath else {
            completion(false, "Failed to create runtime config")
            return
        }
        
        // Start the proxy process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: proxyBinary)
        process.arguments = ["-config", configPath]
        
        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            proxyProcess = process
            
            // Wait for proxy to initialize (dnscrypt-proxy needs time to connect to DoH servers)
            // We'll check if it's running and give it time to initialize
            var initialized = false
            for attempt in 1...30 {
                Thread.sleep(forTimeInterval: 1.0)
                
                if !process.isRunning {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    completion(false, "Proxy crashed during startup: \(errorOutput)")
                    return
                }
                
                // Check if port is listening (indicates proxy is ready)
                if isPortListening(port: proxyPort) {
                    initialized = true
                    NSLog("Proxy initialized after \(attempt) seconds")
                    break
                }
            }
            
            if initialized {
                completion(true, "Proxy started on \(proxyAddress):\(proxyPort)")
            } else {
                process.terminate()
                completion(false, "Proxy started but failed to initialize within 30 seconds")
            }
        } catch {
            completion(false, "Failed to start proxy: \(error.localizedDescription)")
        }
    }
    
    /// Stop the proxy
    func stopProxy() {
        if let process = proxyProcess, process.isRunning {
            process.terminate()
            // Wait a bit for clean shutdown
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                process.interrupt()
            }
        }
        proxyProcess = nil
    }
    
    /// Get the local proxy address to set as system DNS
    func getProxyDNSAddress() -> String {
        return proxyAddress
    }
    
    // MARK: - Private Helpers
    
    private func isPortListening(port: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", ":\(port)", "-sTCP:LISTEN"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func removeQuarantine(from path: String) {
        let task = Process()
        task.launchPath = "/usr/bin/xattr"
        task.arguments = ["-d", "com.apple.quarantine", path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("Failed to remove quarantine: \(error)")
        }
    }
    
    private func getProxyBinaryPath() -> String? {
        // Try bundle resources first
        if let path = Bundle.main.path(forResource: "dnscrypt-proxy", ofType: nil, inDirectory: "proxy") {
            return path
        }
        // Try direct resource path
        if let resourcePath = Bundle.main.resourcePath {
            let proxyPath = resourcePath + "/proxy/dnscrypt-proxy"
            if FileManager.default.fileExists(atPath: proxyPath) {
                return proxyPath
            }
        }
        return nil
    }
    
    private func getConfigTemplatePath() -> String? {
        // Try bundle resources first
        if let path = Bundle.main.path(forResource: "dnscrypt-proxy", ofType: "toml", inDirectory: "proxy") {
            return path
        }
        // Try direct resource path
        if let resourcePath = Bundle.main.resourcePath {
            let configPath = resourcePath + "/proxy/dnscrypt-proxy.toml"
            if FileManager.default.fileExists(atPath: configPath) {
                return configPath
            }
        }
        return nil
    }
    
    private func createRuntimeConfig(serverURL: String, templatePath: String) -> String? {
        do {
            var config = try String(contentsOfFile: templatePath, encoding: .utf8)
            
            // Determine server type and create appropriate stamp
            let serverName: String
            let stamp: String
            
            if serverURL.lowercased().hasPrefix("https://") {
                // DoH server
                serverName = "custom-doh"
                stamp = createDoHStamp(url: serverURL)
            } else if serverURL.lowercased().hasPrefix("tls://") {
                // DoT server
                serverName = "custom-dot"
                let host = String(serverURL.dropFirst("tls://".count))
                stamp = createDoTStamp(host: host)
            } else {
                return nil
            }
            
            // Add custom server configuration
            let customServerConfig = """
            
            [static.'\(serverName)']
            stamp = '\(stamp)'
            """
            
            config += customServerConfig
            
            // Set server_names to use our custom server
            // Replace the existing server_names line
            if let range = config.range(of: "server_names = ['cloudflare']") {
                config.replaceSubrange(range, with: "server_names = ['\(serverName)']")
            } else if let range = config.range(of: "# server_names = ['cloudflare', 'google']") {
                config.replaceSubrange(range, with: "server_names = ['\(serverName)']")
            }
            
            // Write to temporary location
            let tempDir = NSTemporaryDirectory()
            let runtimeConfigPath = tempDir + "dnscrypt-proxy-runtime.toml"
            try config.write(toFile: runtimeConfigPath, atomically: true, encoding: .utf8)
            
            return runtimeConfigPath
        } catch {
            NSLog("Failed to create runtime config: \(error)")
            return nil
        }
    }
    
    private func createDoHStamp(url: String) -> String {
        // For simplicity, we'll use a basic stamp format
        // In production, you'd want to properly encode the stamp
        // For now, we'll use well-known stamps or a simple format
        
        // Map common DoH servers to their stamps
        let knownStamps: [String: String] = [
            "https://dns.cloudflare.com/dns-query": "sdns://AgcAAAAAAAAABzEuMS4xLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5",
            "https://dns.google/dns-query": "sdns://AgUAAAAAAAAAACAe9iTP_15r07rd8_3b_epWVGfjdymdx-5mdRZvMAzBuQ5kbnMuZ29vZ2xlLmNvbQ0vZXhwZXJpbWVudGFs",
            "https://dns.quad9.net/dns-query": "sdns://AgEAAAAAAAAAACA-GhoPbFPz6XpJLVcIS1uYBwWe4FerFQWHb9g_2j24OBBkbnM5LnF1YWQ5Lm5ldDo0NDMKL2Rucy1xdWVyeQ",
            "https://dns.adguard.com/dns-query": "sdns://AgcAAAAAAAAADzk0LjE0MC4xNC4xNDo0NDMAD2Rucy5hZGd1YXJkLmNvbQovZG5zLXF1ZXJ5",
            "https://dns.nextdns.io/dns-query": "sdns://AgcAAAAAAAAAAAAPZG5zLm5leHRkbnMuaW8KL2Rucy1xdWVyeQ"
        ]
        
        if let stamp = knownStamps[url] {
            return stamp
        }
        
        // For unknown URLs, try to extract host and path
        if let urlComponents = URLComponents(string: url),
           let host = urlComponents.host {
            let path = urlComponents.path.isEmpty ? "/dns-query" : urlComponents.path
            // Create a basic DoH stamp (this is simplified)
            // Format: sdns://AgcAAAAAAAAA[base64 encoded data]
            let stampData = "AgcAAAAAAAAAAAAA\(host)\(path)"
            if let data = stampData.data(using: .utf8) {
                return "sdns://" + data.base64EncodedString()
            }
        }
        
        // Fallback to Cloudflare
        return "sdns://AgcAAAAAAAAABzEuMS4xLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5"
    }
    
    private func createDoTStamp(host: String) -> String {
        // Map common DoT servers to their stamps
        let knownStamps: [String: String] = [
            "1dot1dot1dot1.cloudflare-dns.com": "sdns://AwcAAAAAAAAADzEuMS4xLjE6ODUzIDEuMC4wLjE6ODUzIFsyNjA2OjQ3MDA6NDcwMDo6MTExMV06ODUzIFsyNjA2OjQ3MDA6NDcwMDo6MTAwMV06ODUzIB5kbnMuY2xvdWRmbGFyZS5jb20",
            "dns.google": "sdns://AwUAAAAAAAAAAAAACGRucy5nb29nbGU",
            "dns.quad9.net": "sdns://AwEAAAAAAAAAAAANZG5zLnF1YWQ5Lm5ldA"
        ]
        
        if let stamp = knownStamps[host] {
            return stamp
        }
        
        // Create a basic DoT stamp
        if let data = "AwcAAAAAAAAAAAAA\(host)".data(using: .utf8) {
            return "sdns://" + data.base64EncodedString()
        }
        
        // Fallback
        return "sdns://AwcAAAAAAAAADzEuMS4xLjE6ODUzIDEuMC4wLjE6ODUzIFsyNjA2OjQ3MDA6NDcwMDo6MTExMV06ODUzIFsyNjA2OjQ3MDA6NDcwMDo6MTAwMV06ODUzIB5kbnMuY2xvdWRmbGFyZS5jb20"
    }
}
