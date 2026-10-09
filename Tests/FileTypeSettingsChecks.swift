import Foundation

func runFileTypeSettingsChecks(_ check: (Bool, String) -> Void) {
    let formats = ["png", "jpg", "svg", "raw-test"]
    var associations = Dictionary(uniqueKeysWithValues: formats.map { ($0, FileTypeAssociation(applicationName: "预览", isViaView: false)) })
    associations["png"] = FileTypeAssociation(applicationName: "ViaView", isViaView: true)
    // Display names alone must not be mistaken for the application's bundle identity.
    associations["jpg"] = FileTypeAssociation(applicationName: "ViaView", isViaView: false)
    var calls: [String] = []
    var callbacks: [(Error?) -> Void] = []
    let client = FileTypeAssociationClient(read: { associations[$0]! }, set: { ext, done in calls.append(ext); callbacks.append(done) })
    let model = FileTypeSettingsModel(formats: formats, client: client)
    check(model.configuredCount == 1, "file associations use app identity, not its display name")
    model.setAll()
    check(calls == ["jpg"] && model.busy == "jpg" && model.total == 3, "batch skips configured types and starts only one system request")
    model.setAll(); model.setDefault("svg")
    check(calls == ["jpg"], "repeated clicks cannot start overlapping association requests")
    associations["jpg"] = FileTypeAssociation(applicationName: "ViaView", isViaView: true)
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
    associations["svg"] = FileTypeAssociation(applicationName: "ViaView", isViaView: true)
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == "raw-test" }
    associations["raw-test"] = FileTypeAssociation(applicationName: "ViaView", isViaView: true)
    callbacks.removeFirst()(nil)
    _ = waitForCheck { model.busy == nil }
    check(model.allConfigured && model.message == "已将 2 种文件类型设为使用 ViaView 打开。", "successful retry refreshes all checkmarks and final result")
    let count = calls.count
    model.setAll(); model.setDefault("unknown")
    check(calls.count == count && model.busy == nil, "already configured and unknown formats do not write system defaults")
    associations["png"] = FileTypeAssociation(applicationName: "预览", isViaView: false)
    model.refresh(); model.setDefault("png")
    check(model.total == 1 && calls.last == "png" && !model.allConfigured, "external association changes refresh and single-format setting still works")
    callbacks.removeFirst()(NSError(domain: "Check", code: 2, userInfo: [NSLocalizedDescriptionKey: "系统无法识别此文件类型。 "]))
    _ = waitForCheck { model.busy == nil }
    check(model.message.contains("PNG") && model.message.contains("系统无法识别"), "unavailable types return an actionable per-format error")
}
