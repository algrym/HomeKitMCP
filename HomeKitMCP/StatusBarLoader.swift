import Foundation

#if targetEnvironment(macCatalyst)
/// Loads the AppKit plugin bundle at runtime and sets up the menu bar status item.
enum StatusBarLoader {
    static private(set) var bridge: StatusBarBridgeProtocol?

    static func load() {
        guard bridge == nil else { return }

        guard let plugInsURL = Bundle.main.builtInPlugInsURL else {
            Log.error("StatusBarLoader: no PlugIns directory found")
            return
        }

        let bundleURL = plugInsURL.appendingPathComponent("StatusBarPlugin.bundle")

        guard let bundle = Bundle(url: bundleURL) else {
            Log.error("StatusBarLoader: could not create bundle at \(bundleURL)")
            return
        }

        guard bundle.load() else {
            Log.error("StatusBarLoader: failed to load plugin bundle")
            return
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            Log.error("StatusBarLoader: principal class not found or not NSObject")
            return
        }

        guard let instance = principalClass.init() as? StatusBarBridgeProtocol else {
            Log.error("StatusBarLoader: principal class does not conform to StatusBarBridgeProtocol")
            return
        }

        bridge = instance
        instance.setupStatusBar()
        Log.info("StatusBarLoader: menu bar item active")
    }
}
#endif
