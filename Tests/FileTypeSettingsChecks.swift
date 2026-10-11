import Foundation

func runFileTypeSettingsChecks(_ check: (Bool, String) -> Void) {
    let own = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/ViaView.app"), id: "test.viaview", name: "ViaView")
    let preview = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/Preview.app"), id: "com.apple.Preview", name: "预览")
    let impostor = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/Other.app"), id: "test.other", name: "ViaView")
    let formats = ["png", "jpg", "svg", "raw-test"]
    var associations = Dictionary(uniqueKeysWithValues: formats.map { ($0, preview) })
    associations["png"] = own
    // Display names alone must not be mistaken for the application's bundle identity.
    associations["jpg"] = impostor
    var calls: [String] = []
    var callbacks: [(Error?) -> Void] = []
    let client = FileTypeAssociationClient(ownApplication: own, read: { associations[$0] }, applications: { _ in [own, preview] }, set: { ext, _, done in calls.append(ext); callbacks.append(done) })
    let model = FileTypeSettingsModel(formats: formats, client: client)
    check(model.configuredCount == 1, "file associations use app identity, not its display name")
    model.setAll()
    check(calls == ["jpg"] && model.busy == "jpg" && model.total == 3, "batch skips configured types and starts only one system request")
    model.setAll(); model.setDefault("svg")
    check(calls == ["jpg"], "repeated clicks cannot start overlapping association requests")
    associations["jpg"] = own
    callbacks.removeFirst()(nil)
    _ = waitForCheck { calls.count == 2 }
    check(calls == ["jpg", "svg"] && model.completed == 1 && model.configuredCount == 2, "batch advances with visible progress after a confirmed success")
    callbacks.removeFirst()(NSError(domain: "Check", code: 1, userInfo: [NSLocalizedDescriptionKey: "用户取消了系统确认。 "]))
    _ = waitForCheck { calls.count == 3 }
    check(calls == ["jpg", "svg", "raw-test"], "a rejected type does not stop later types")
    // A nil system error still must not produce a false success badge.
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(model.completed == 3 && model.message.contains("已设置 1 种，2 种未完成") && model.message.contains("SVG") && model.message.contains("RAW-TEST") && !model.allConfigured,
          "partial results identify every failure, including unchanged handlers")
    model.setAll()
    check(calls.last == "svg" && model.total == 2, "retry only changes unfinished formats")
    associations["svg"] = own
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == "raw-test" }
    associations["raw-test"] = own
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(model.allConfigured && model.message == "已将 2 种文件类型设为使用 ViaView 打开。", "successful retry refreshes all checkmarks and final result")
    let count = calls.count
    model.setAll(); model.setDefault("unknown")
    check(calls.count == count && model.busy == nil, "already configured and unknown formats do not write system defaults")
    associations["png"] = preview
    model.refresh(); model.setDefault("png")
    check(model.total == 1 && calls.last == "png" && !model.allConfigured, "external association changes refresh and single-format setting still works")
    callbacks.removeFirst()(NSError(domain: "Check", code: 2, userInfo: [NSLocalizedDescriptionKey: "系统无法识别此文件类型。 "]))
    _ = waitForCheck { model.busy == nil }
    check(model.message.contains("PNG") && model.message.contains("系统无法识别"), "unavailable types return an actionable per-format error")
    runFileTypeUnbindingChecks(check)
}

private func runFileTypeUnbindingChecks(_ check: (Bool, String) -> Void) {
    let own = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/ViaView.app"), id: "test.viaview", name: "ViaView")
    let preview = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/Preview.app"), id: "com.apple.Preview", name: "预览")
    let browser = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/Browser.app"), id: "test.browser", name: "Browser")
    let impostor = FileTypeApplication(url: URL(fileURLWithPath: "/Applications/Other.app"), id: "test.other", name: "预览")
    let formats = ["png", "jpg", "svg", "pdf"]
    var associations = ["png": own, "jpg": own, "svg": own, "pdf": browser]
    var calls: [(String, FileTypeApplication)] = []
    var callbacks: [(Error?) -> Void] = []
    let client = FileTypeAssociationClient(ownApplication: own, read: { associations[$0] },
        applications: { ext in ext == "svg" ? [own, browser] : [own, preview, preview, browser] },
        set: { ext, app, done in calls.append((ext, app)); callbacks.append(done) })
    let model = FileTypeSettingsModel(formats: formats + ["png"], client: client)
    check(model.formats == formats && model.configuredCount == 3, "duplicate input formats do not cause duplicate requests")
    check(model.replacementApplications(for: ["png"]) == [preview, browser], "replacement choices exclude ViaView and duplicate bundle identities")
    check(model.replacementApplications(for: ["png", "svg"]) == [browser], "batch recommends applications supporting every requested format")
    check(model.replacementApplications(for: []) == [] && model.replacementApplications(for: ["unknown"]) == [], "empty and unknown selections have no replacement candidates")
    model.unbind(formats, to: own)
    check(calls.isEmpty && model.message.contains("ViaView 以外"), "unbinding rejects ViaView as its own replacement")
    model.unbind([], to: preview); model.unbind(["unknown", "pdf"], to: preview)
    check(calls.isEmpty, "empty, unknown and already externally bound formats do not change defaults")
    model.unbind(formats, to: preview)
    check(calls.count == 1 && calls[0].0 == "png" && calls[0].1 == preview && model.total == 3,
          "batch unbind only queues ViaView types and passes the chosen application")
    model.unbind(formats, to: browser); model.setAll(); model.setDefault("pdf")
    check(calls.count == 1 && model.progressText.contains("预览"), "unbinding prevents overlapping writes and keeps its target stable")
    associations["png"] = preview
    callbacks.removeFirst()(nil)
    _ = waitForCheck { calls.count == 2 }
    check(model.completed == 1 && model.configuredCount == 2 && calls[1].0 == "jpg", "successful unbind refreshes the row and advances serially")
    callbacks.removeFirst()(NSError(domain: "Check", code: 1, userInfo: [NSLocalizedDescriptionKey: "用户取消了系统确认。 "]))
    _ = waitForCheck { calls.count == 3 }
    // Matching display names must not produce false success for the wrong app.
    associations["svg"] = impostor
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(model.message.contains("已设置 1 种，2 种未完成") && model.message.contains("JPG") && model.message.contains("SVG") && model.message.contains("用户取消"),
          "partial unbind reports cancellation and rejects same-name wrong-app results")
    check(associations["pdf"] == browser && calls.map { $0.0 } == ["png", "jpg", "svg"], "unbinding preserves defaults owned by other applications")
    model.unbind(formats, to: preview)
    check(model.total == 1 && calls.last?.0 == "jpg", "retry only touches types still owned by ViaView")
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(model.message.contains("系统尚未更改为所选应用"), "nil callback error with unchanged default is still a failure")
    model.unbind(["jpg"], to: preview)
    associations["jpg"] = preview
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(model.message == "已解绑 1 种文件类型，改用 预览 打开。" && model.configuredCount == 0, "single-format unbind succeeds and enables rebinding")
    model.setDefault("jpg")
    check(calls.last?.1 == own, "a previously unbound format can be rebound to ViaView")
    associations["jpg"] = own
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    associations["png"] = own; associations["svg"] = own
    model.unbind(formats, to: preview)
    associations["jpg"] = browser; associations["svg"] = nil
    associations["png"] = preview
    let count = calls.count
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(calls.count == count && model.completed == 3 && model.message.contains("已跳过 2 种") && associations["jpg"] == browser,
          "queued unbinding skips externally changed and missing defaults without overwriting them")
    var emptyWrites = 0
    let empty = FileTypeSettingsModel(formats: ["png"], client: FileTypeAssociationClient(ownApplication: own, read: { _ in nil }, applications: { _ in [] }, set: { _, _, _ in emptyWrites += 1 }))
    empty.unbind(["png"], to: preview)
    check(emptyWrites == 0 && empty.configuredCount == 0 && empty.busy == nil && empty.replacementApplications(for: ["png"]).isEmpty, "no default or installed alternatives is an actionable empty state")
    check(FileTypeApplication.read(at: URL(string: "https://example.com/Fake.app")!) == nil && FileTypeApplication.read(at: URL(fileURLWithPath: "/tmp/not-an-application")) == nil,
          "application selection rejects remote URLs and non-application files")
    var invalidError: Error?
    FileTypeAssociationClient.system.set("png", FileTypeApplication(url: URL(fileURLWithPath: "/tmp/viaview-missing-application.app"), id: "test.missing", name: "Missing")) { invalidError = $0 }
    check(invalidError?.localizedDescription.contains("不可用") == true, "system adapter rejects an unavailable target before modifying defaults")
}
