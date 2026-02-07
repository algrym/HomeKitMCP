import AppKit

@objc(StatusBarController)
class StatusBarController: NSObject, StatusBarBridgeProtocol {
    private var statusItem: NSStatusItem!

    func setupStatusBar() {
        DispatchQueue.main.async { [weak self] in
            self?.createStatusItem()
        }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        if let image = NSImage(systemSymbolName: "poweroutlet.type.k.fill", accessibilityDescription: "HomeKit MCP") {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "HomeKit MCP Server", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusItem = NSMenuItem(title: "● Running", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu

        // Hide dock icon — run as accessory/agent app
        NSApp.setActivationPolicy(.accessory)
    }

    func hideAllWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window !== self.statusItem.button?.window {
                window.orderOut(nil)
                window.setIsVisible(false)
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(self)
    }
}
