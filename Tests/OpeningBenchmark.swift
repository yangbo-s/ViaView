import AppKit
import ViewerCore

/// Optional manual benchmark: AppKitChecks --benchmark /absolute/path/to/photo.jpg
func runOpeningBenchmark(_ url: URL) {
    let pipeline = ImagePipeline()
    var failures = 0
    for iteration in 0..<3 {
        let viewer = ViewerController(imagePipeline: pipeline)
        let start = ProcessInfo.processInfo.systemUptime
        viewer.openURLs([url]); viewer.showWindow(nil)
        var blankWasVisible = viewer.window?.isVisible == true && viewer.canvas.image == nil
        let deadline = Date(timeIntervalSinceNow: 10)
        while viewer.asset == nil && viewer.isLoading && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
            if viewer.window?.isVisible == true && (viewer.scroll.isHidden || viewer.canvas.image == nil) { blankWasVisible = true }
        }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let ready = viewer.asset?.url == url && viewer.window?.isVisible == true
        print(String(format: "OPEN %@ ready=%@ blankVisible=%@ %.1fms", iteration == 0 ? "cold" : "cached", String(ready), String(blankWasVisible), elapsed))
        if !ready || blankWasVisible { failures += 1 }
        viewer.close()
    }
    exit(failures == 0 ? 0 : 1)
}
