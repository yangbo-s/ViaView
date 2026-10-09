import AppKit
import Sparkle

func runUpdateSettingsChecks(_ check: (Bool, String) -> Void) {
    let domain = "ViaView.UpdateChecks.\(UUID().uuidString)"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
    let contents = root.appendingPathComponent("UpdateChecks.app/Contents")
    let store = UserDefaults(suiteName: domain)!
    defer {
        store.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: root)
    }
    do {
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": domain, "CFBundleName": "UpdateChecks",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "0.0.1",
            "SUEnableAutomaticChecks": true, "SUAutomaticallyUpdate": false,
            "SUFeedURL": "https://example.invalid/appcast.xml",
            "SUPublicEDKey": "FBLR74mUUD8yd8YxjXs44Gq/Gky1Yj2vhtfJn8mhZMU="
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = Bundle(url: contents.deletingLastPathComponent())!
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        let model = UpdateSettingsModel(updater: updater)
        check(model.automaticallyChecksForUpdates && !model.automaticallyInstallsUpdates && model.allowsAutomaticUpdates,
              "update defaults allow checking but require opt-in for automatic installation")
        check(!model.canCheckForUpdates && model.lastUpdateCheckDate == nil,
              "manual check is disabled until the updater starts, without a fabricated last check date")
        model.checkForUpdates()
        check(!updater.sessionInProgress, "unavailable manual check does not start an update session")
        model.setAutomaticallyInstallsUpdates(true)
        check(updater.automaticallyDownloadsUpdates && model.automaticallyInstallsUpdates && store.bool(forKey: "SUAutomaticallyUpdate"),
              "automatic install writes Sparkle's real persisted preference and updates the UI")
        model.setAutomaticallyChecksForUpdates(false)
        check(!updater.automaticallyChecksForUpdates && !model.automaticallyChecksForUpdates && !model.allowsAutomaticUpdates && !model.automaticallyInstallsUpdates,
              "turning off automatic checks disables automatic install and synchronizes its effective state")
        model.setAutomaticallyInstallsUpdates(false)
        check(store.bool(forKey: "SUAutomaticallyUpdate"), "disabled install control preserves the user's saved choice")
        model.setAutomaticallyChecksForUpdates(true)
        check(model.allowsAutomaticUpdates && model.automaticallyInstallsUpdates,
              "re-enabling checks restores the previous automatic install choice")
        updater.automaticallyDownloadsUpdates = false
        updater.automaticallyChecksForUpdates = false
        check(!model.automaticallyChecksForUpdates && !model.automaticallyInstallsUpdates,
              "settings observe changes originating outside the settings view")
        let reopened = UpdateSettingsModel(updater: updater)
        check(!reopened.automaticallyChecksForUpdates && !reopened.automaticallyInstallsUpdates,
              "reopening settings preserves explicit choices without resetting defaults")
        let restarted = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        check(!restarted.automaticallyChecksForUpdates && !restarted.automaticallyDownloadsUpdates,
              "a new updater reads persisted preferences instead of initial plist defaults")
        check(!restarted.sendsSystemProfile, "update checks do not send a system profile by default")
        try updater.start()
        check(model.canCheckForUpdates && !model.automaticallyChecksForUpdates,
              "manual check becomes available even with automatic checks disabled")
        try updater.start()
        check(model.canCheckForUpdates && !updater.sessionInProgress,
              "starting an updater twice is safe and does not force a background check")
    } catch {
        check(false, "update settings fixture failed: \(error)")
    }
}
