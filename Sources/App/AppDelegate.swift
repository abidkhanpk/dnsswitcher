import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuBarController?
    private var prefsWC: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon if LSUIElement is not set yet
        NSApp.setActivationPolicy(.accessory)

        let controller = MenuBarController()
        controller.buildMenu()
        self.menuController = controller

        // Attempt to bless/install helper on first launch
        DNSChangerClient.shared.ensureHelperBlessed { success in
            if !success {
                NSLog("DNSChanger: Failed to bless helper. DNS actions may require admin.")
            }
        }

        // Listen for profile updates to refresh menu
        NotificationCenter.default.addObserver(self, selector: #selector(refreshProfiles), name: .profilesUpdated, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    // Handle custom URL scheme: dnschanger://apply?... or dnschanger://disable
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "dnschanger" else { continue }
            let action = (url.host ?? "").lowercased()
            switch action {
            case "disable":
                DNSChangerClient.shared.clearDNS { success, message in
                    self.menuController?.rebuildProfilesSection()
                    self.notify(title: success ? "Default DNS Enabled" : "Failed", body: message)
                }
            case "apply", "":
                let servers = extractServers(from: url)
                if servers.isEmpty {
                    self.notify(title: "Failed", body: "No servers provided")
                    continue
                }
                DNSChangerClient.shared.applyDNS(servers: servers) { success, message in
                    self.notify(title: success ? "DNS Applied" : "Failed", body: message)
                }
            default:
                continue
            }
        }
    }

    // Accept multiple forms:
    // dnschanger://apply?servers=94.140.14.14,94.140.15.15
    // dnschanger://apply?doh=https%3A%2F%2Fdns.adguard.com%2Fdns-query
    // dnschanger://apply?dot=dns.adguard.com
    // dnschanger://apply/https:%2F%2Fdns.adguard.com%2Fdns-query
    // dnschanger://apply/94.140.14.14,94.140.15.15
    private func extractServers(from url: URL) -> [String] {
        var results: [String] = []
        func addTokens(_ value: String) {
            value.split(separator: ",").forEach { raw in
                var token = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if token.isEmpty { return }
                // Support doh: and dot: prefixes for convenience
                if token.lowercased().hasPrefix("doh:") {
                    token = "https://" + String(token.dropFirst(4))
                } else if token.lowercased().hasPrefix("dot:") {
                    token = "tls://" + String(token.dropFirst(4))
                } else if !token.lowercased().hasPrefix("https://") && !token.lowercased().hasPrefix("tls://") {
                    // If it's a bare hostname with a dot, treat as DoT host
                    if token.contains(".") && token.range(of: "^[-A-Za-z0-9_.:]+$", options: .regularExpression) != nil {
                        token = "tls://" + token
                    }
                }
                if !results.contains(token) { results.append(token) }
            }
        }
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let items = comps.queryItems ?? []
            for key in ["servers", "server", "ip", "ips", "doh", "dot", "url", "host", "hosts"] {
                if let v = items.first(where: { $0.name.lowercased() == key })?.value { addTokens(v) }
            }
        }
        // Fallback to path payload
        let pathPart = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !pathPart.isEmpty { addTokens(pathPart.removingPercentEncoding ?? pathPart) }
        return results
    }

    private func notify(title: String, body: String) {
        let n = NSUserNotification()
        n.title = title
        n.informativeText = body
        NSUserNotificationCenter.default.deliver(n)
    }

    @objc func showPreferencesWindow() {
        if prefsWC == nil {
            let hosting = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "DNSChanger Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 560, height: 460))
            window.center()
            prefsWC = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWC?.showWindow(nil)
        prefsWC?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func refreshProfiles() {
        menuController?.rebuildProfilesSection()
    }
}
