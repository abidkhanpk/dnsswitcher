import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuBarController?

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

    @objc private func refreshProfiles() {
        menuController?.rebuildProfilesSection()
    }
}
