import AppKit

func runThemeSettingsChecks(_ check: (Bool, String) -> Void) {
    let domain = "ViaView.SettingsChecks.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: domain)!
    defer { store.removePersistentDomain(forName: domain) }
    AppSettings.register(in: store, domain: domain)
    let initial: [String: Any] = [
        "themeMode": "system", "wrap": true, "slideDelay": 3,
        "selectOnDrag": false, "doubleClickZoom": true, "smoothRendering": true,
        "swipeNavigate": true, "zoomSensitivity": 1.0, "checkerboard": true,
        "openInNewWindow": false, "restoreWindows": false, "quitLastWindow": false,
        "preloadImages": true, "cacheMB": 256, "editorBundleID": "com.apple.Preview",
        "fileListGrid": false, "bookmarks": [Data](), "openImagePaths": [String]()
    ]
    check(initial.allSatisfy { key, value in
        (store.object(forKey: key) as? NSObject)?.isEqual(value) == true
    }, "fresh install uses every documented preference default, with no bookmarks or restored images")
    check(AppSettings.theme(in: store) == .system && store.persistentDomain(forName: domain)?.isEmpty != false,
          "first launch follows the system without writing user choices")
    store.register(defaults: ["darkCanvas": false])
    AppSettings.register(in: store, domain: domain)
    check(AppSettings.theme(in: store) == .system, "legacy registration default is not mistaken for a saved light-theme preference")
    store.set("dark", forKey: "themeMode"); store.set(true, forKey: "openInNewWindow")
    store.set(512, forKey: "cacheMB"); store.set("example.editor", forKey: "editorBundleID")
    store.set([Data([1, 2])], forKey: "bookmarks")
    store.set(["/example/picture.png"], forKey: "openImagePaths")
    AppSettings.register(in: store, domain: domain)
    check(AppSettings.theme(in: store) == .dark && store.bool(forKey: "openInNewWindow") && store.integer(forKey: "cacheMB") == 512 && store.string(forKey: "editorBundleID") == "example.editor" && (store.array(forKey: "bookmarks") as? [Data]) == [Data([1, 2])] && store.stringArray(forKey: "openImagePaths") == ["/example/picture.png"],
          "restart and upgrade preserve explicit settings, file grants and saved session")
    for legacy in [true, false] {
        store.removePersistentDomain(forName: domain)
        store.set(legacy, forKey: "darkCanvas")
        AppSettings.register(in: store, domain: domain)
        check(AppSettings.theme(in: store) == (legacy ? .dark : .light), "saved legacy canvas choice migrates: dark=\(legacy)")
        store.set("system", forKey: "themeMode")
        AppSettings.register(in: store, domain: domain)
        check(AppSettings.theme(in: store) == .system, "explicit system theme wins over legacy canvas on repeated registration")
    }
    store.set("unsupported-theme", forKey: "themeMode")
    check(AppSettings.theme(in: store) == .system, "unknown theme values safely resolve to system appearance")
    check(AppTheme.system.appearance == nil && AppTheme.light.appearance?.name == .aqua && AppTheme.dark.appearance?.name == .darkAqua,
          "theme modes use native application appearance and system inheritance")

    let prior = NSApp.appearance
    defer { NSApp.appearance = prior }
    NSApp.appearance = AppTheme.light.appearance
    let viewer = ViewerController()
    let settings = SettingsWindowController()
    let panel = ViewerToolPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.contentView = NSView()
    defer { panel.close(); settings.close(); viewer.close() }
    viewer.showWindow(nil)
    settings.showWindow(nil)
    panel.orderFront(nil)
    func dark(_ view: NSAppearanceCustomization) -> Bool { view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    check(!viewer.usesDarkAppearance && !dark(settings.window!) && !dark(panel), "light theme reaches image, settings and tool windows")
    NSApp.appearance = AppTheme.dark.appearance
    check(waitForCheck { viewer.usesDarkAppearance && dark(settings.window!) && dark(panel) && viewer.window?.backgroundColor == NSColor(white: 0.10, alpha: 1) },
          "an inherited appearance change refreshes existing windows and canvas automatically")
    check(viewer.nameLabel.textColor == .white, "dark canvas keeps an empty or transparent image title readable")
    NSApp.appearance = AppTheme.light.appearance
    check(waitForCheck { !viewer.usesDarkAppearance && viewer.window?.backgroundColor == NSColor(white: 0.93, alpha: 1) && viewer.nameLabel.textColor == .black },
          "switching back to light refreshes the canvas and title without reopening")
    viewer.refreshAppearance(fullScreen: true)
    NSApp.appearance = AppTheme.dark.appearance
    NSApp.appearance = AppTheme.light.appearance
    check(viewer.window?.backgroundColor == .black && viewer.usesDarkAppearance && !dark(settings.window!),
          "fullscreen stays black while settings follow the chosen application theme")
    viewer.refreshAppearance(fullScreen: false)
    check(!viewer.usesDarkAppearance && viewer.window?.backgroundColor == NSColor(white: 0.93, alpha: 1),
          "leaving fullscreen removes its local dark override")
    NSApp.appearance = AppTheme.system.appearance
    viewer.refreshAppearance()
    check(NSApp.appearance == nil && viewer.window?.appearance == nil && viewer.stage.appearance == nil && settings.window?.appearance == nil && panel.appearance == nil,
          "system mode clears all windowed appearance overrides")
    check(dark(viewer.stage) == dark(NSApp) && dark(settings.window!) == dark(NSApp) && dark(panel) == dark(NSApp),
          "system mode matches the actual macOS appearance across all windows")
}
