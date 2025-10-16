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

        // Disable item to use default DNS
        let disableItem = NSMenuItem(title: "Use Default DNS (Disable)", action: #selector(disableDNS), keyEquivalent: "")
        disableItem.target = self
        menu.addItem(disableItem)

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
        if let hiddenData = UserDefaults.standard.data(forKey: "hiddenDefaultProfileIDs"),
           let hiddenIDs = try? JSONDecoder().decode([UUID].self, from: hiddenData) {
            let hiddenSet = Set(hiddenIDs)
            list.removeAll { hiddenSet.contains($0.id) }
        }
        if let data = UserDefaults.standard.data(forKey: "customProfiles"),
           let custom = try? JSONDecoder().decode([DNSProfile].self, from: data) {
            list.append(contentsOf: custom)
        }
        profiles = list
        if activeProfileName == nil || !profiles.contains(where: { $0.name == activeProfileName }) {
            activeProfileName = profiles.first?.name
        }
    }

    @objc private func didSelectProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? DNSProfile else { return }
        activeProfileName = profile.name
        rebuildMenu()
        // Auto-apply on selection to ensure consistency between UI and system state
        DNSChangerClient.shared.applyDNS(servers: profile.servers) { success, message in
            self.notifyUser(title: success ? "DNS Applied" : "Failed", informative: message)
        }
    }

    @objc private func disableDNS() {
        DNSChangerClient.shared.clearDNS { success, message in
            self.notifyUser(title: success ? "Default DNS Enabled" : "Failed", informative: message)
        }
    }

    @objc private func openPreferences() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showPreferencesWindow()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(#selector(AppDelegate.showPreferencesWindow), to: nil, from: nil)
        }
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
