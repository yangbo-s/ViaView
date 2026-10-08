import Foundation

func runChecks() -> Int32 {
    let runner = CheckRunner()
    do {
        let fixtures = try CheckFixtures()
        defer {
            do { try fixtures.remove() }
            catch { runner.recordFailure("清理临时测试夹具", error: error) }
        }
        runGalleryChecks(runner, fixtures: fixtures)
        runImagingChecks(runner, fixtures: fixtures)
        runViewportSVGChecks(runner, fixtures: fixtures)
        runTagsColorChecks(runner, fixtures: fixtures)
    } catch {
        runner.recordFailure("创建测试夹具", error: error)
    }
    runner.printSummary()
    return runner.failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE
}

// The function returns only after fixture cleanup, including failed-check paths.
exit(runChecks())
