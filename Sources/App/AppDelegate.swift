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
