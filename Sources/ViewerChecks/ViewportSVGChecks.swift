import Foundation
import CoreGraphics
import ViewerCore

func runViewportSVGChecks(_ runner: CheckRunner, fixtures: CheckFixtures) {
    let check = runner.check
    let folder = fixtures.folder

    check("SVG 校验及损坏矢量图拒绝") {
        let p = folder.appendingPathComponent("vector.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'><rect width='40' height='20'/></svg>".utf8).write(to: p)
        guard try ImagePipeline.decode(p).isSVG else { return false }
        try Data("<html><svg/></html>".utf8).write(to: p)
        do { _ = try ImagePipeline.decode(p); return false } catch { return true }
    }
    check("图片窗口三个缩放区间与连续边界") {
        let g = ImageWindowGeometry(image: CGSize(width: 1000, height: 1000), available: CGSize(width: 1200, height: 800))
        return g.windowSize(at: 0.1) == CGSize(width: 320, height: 320)
            && g.windowSize(at: 0.5) == CGSize(width: 500, height: 500)
            && g.windowSize(at: 2) == CGSize(width: 800, height: 800)
            && abs(g.windowSize(at: 0.320001).width - g.windowSize(at: 0.319999).width) < 0.01
            && abs(g.windowSize(at: 0.800001).width - g.windowSize(at: 0.799999).width) < 0.01
    }
    check("横竖长图在所有倍率保持比例且不超屏幕") {
        for size in [CGSize(width: 1600, height: 900), CGSize(width: 900, height: 1600), CGSize(width: 10000, height: 100), CGSize(width: 100, height: 10000)] {
            let g = ImageWindowGeometry(image: size, available: CGSize(width: 1300, height: 780))
            for scale in [0.001, 0.1, 0.5, 1, 32] {
                let result = g.windowSize(at: scale)
                if abs(result.width / result.height - size.width / size.height) > 0.00001 || result.width > 1300.001 || result.height > 780.001 { return false }
            }
        }
        return true
    }
    check("连续缩放单调无过冲、反向可即时响应") {
        var z = SmoothZoom(); z.reset(0.2); z.aim(3)
        var last: CGFloat = 0.2
        for _ in 0..<100 { let next = z.advance(seconds: 1.0/120); if next < last || next > 3.000001 { return false }; last = next }
        z.aim(0.1); let reverse = z.advance(seconds: 1.0/120)
        return reverse < last && reverse > 0.1
    }
    check("缩放滤波不依赖60Hz或120Hz刷新率") {
        var a = SmoothZoom(), b = SmoothZoom(); a.reset(1); b.reset(1); a.aim(4); b.aim(4)
        var x: CGFloat = 1, y: CGFloat = 1
        for _ in 0..<12 { x = a.advance(seconds: 1.0/60) }
        for _ in 0..<24 { y = b.advance(seconds: 1.0/120) }
        return abs(x - y) < 0.000001
    }
    check("切图重置取消前一张缩放目标") {
        var z = SmoothZoom(); z.reset(1); z.aim(10); _ = z.advance(seconds: 0.02); z.reset(0.5)
        return z.targetScale == 0.5 && z.isSettled && abs(z.advance(seconds: 1) - 0.5) < 0.000001
    }
    check("SVG viewBox尺寸用于图片窗口比例") {
        let p = folder.appendingPathComponent("aspect.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1600 900'></svg>".utf8).write(to: p)
        let a = try ImagePipeline.decode(p)
        return a.image.size == CGSize(width: 1600, height: 900)
    }
}
