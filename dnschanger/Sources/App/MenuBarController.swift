import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private var profiles: [DNSProfile] = []
    private var activeProfileName: String? {
        get { UserDefaults.standard.string(forKey: "activeProfileName") }
        set { UserDefaults.standard.set(newValue, forKey: "activeProfileName") }
    }

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "DNSChanger")
        }
        loadProfiles()
    }

    func buildMenu() {
        menu.autoenablesItems = false
        rebuildMenu()
        statusItem.menu = menu
    }

    func rebuildProfilesSection() {
        loadProfiles()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // Profiles header
        let header = NSMenuItem()
        header.title = "DNS Profiles"
        header.isEnabled = false
        menu.addItem(header)

        // Profiles list
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(didSelectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            if profile.name == activeProfileName {
                item.state = .on
            }
            menu.addItem(item)
        }

        if profiles.isEmpty {
            let none = NSMenuItem()
            none.title = "No profiles configured"
            none.isEnabled = false
            menu.addItem(none)
        }

        menu.addItem(NSMenuItem.separator())

        // Actions
        let applyItem = NSMenuItem(title: "Apply DNS", action: #selector(applyDNS), keyEquivalent: "")
        applyItem.target = self
        applyItem.isEnabled = activeProfileName != nil
        menu.addItem(applyItem)

        let clearItem = NSMenuItem(title: "Clear DNS", action: #selector(clearDNS), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let flushItem = NSMenuItem(title: "Flush Cache", action: #selector(flushCache), keyEquivalent: "")
        flushItem.target = self
        menu.addItem(flushItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func loadProfiles() {
        var list: [DNSProfile] = DNSProfile.loadDefaultProfiles() ?? []
        if let data = UserDefaults.standard.data(forKey: "customProfiles"),
           let custom = try? JSONDecoder().decode([DNSProfile].self, from: data) {
            list.append(contentsOf: custom)
        }
        profiles = list
        if activeProfileName == nil, let first = profiles.first {
            activeProfileName = first.name
        }
    }

    @objc private func didSelectProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? DNSProfile else { return }
        activeProfileName = profile.name
        rebuildMenu()
    }

    @objc private func applyDNS() {
        guard let name = activeProfileName, let profile = profiles.first(where: { $0.name == name }) else { return }
        DNSChangerClient.shared.applyDNS(servers: profile.servers) { success, message in
            self.notifyUser(title: success ? "DNS Applied" : "Failed", informative: message)
        }
    }

    @objc private func clearDNS() {
        DNSChangerClient.shared.clearDNS { success, message in
            self.notifyUser(title: success ? "DNS Cleared" : "Failed", informative: message)
        }
    }

    @objc private func flushCache() {
        DNSChangerClient.shared.flushDNSCache { success, message in
            self.notifyUser(title: success ? "Cache Flushed" : "Failed", informative: message)
        }
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func notifyUser(title: String, informative: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = informative
        NSUserNotificationCenter.default.deliver(notification)
    }
}
