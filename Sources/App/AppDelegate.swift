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

    // Handle custom URL scheme: dnschanger://apply?servers=... or dnschanger://disable
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "dnschanger" else { continue }
            let host = url.host?.lowercased() ?? ""
            if host == "disable" {
                DNSChangerClient.shared.clearDNS { success, message in
                    self.menuController?.rebuildProfilesSection()
                    self.notify(title: success ? "Default DNS Enabled" : "Failed", body: message)
                }
                continue
            }
            if host == "apply" {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let items = comps.queryItems,
                   let serversStr = items.first(where: { $0.name == "servers" })?.value {
                    // servers may be comma separated
                    let servers = serversStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if servers.isEmpty { self.notify(title: "Failed", body: "No servers provided"); continue }
                    DNSChangerClient.shared.applyDNS(servers: servers) { success, message in
                        self.notify(title: success ? "DNS Applied" : "Failed", body: message)
                    }
                } else {
                    self.notify(title: "Failed", body: "Missing servers parameter")
                }
                continue
            }
        }
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
