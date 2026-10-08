import AppKit

@main enum ViaViewApp {
    static func main() {
        AppSettings.register()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
