import AppKit

// Public AppKit APIs are resolved at runtime so the project also builds with
// Command Line Tools SDKs that predate macOS 26. No private material or shader.
final class GlassChrome: NSView {
    let content = NSView()
    let effect: NSView
    let usesLiquidGlass: Bool

    init(radius: CGFloat = 28) {
        if let type = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = type.init(frame: .zero)
            glass.setValue(content, forKey: "contentView")
            glass.setValue(radius, forKey: "cornerRadius")
            glass.setValue(0, forKey: "style") // NSGlassEffectView.Style.regular
            if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                glass.setValue(true, forKey: "effectIsInteractive")
            }
            effect = glass; usesLiquidGlass = true
        } else {
            let fallback = NSVisualEffectView()
            fallback.material = .hudWindow; fallback.blendingMode = .withinWindow; fallback.state = .active
            fallback.wantsLayer = true; fallback.layer?.cornerRadius = radius; fallback.layer?.masksToBounds = true
            fallback.addSubview(content)
            effect = fallback; usesLiquidGlass = false
        }
        super.init(frame: .zero)
        addSubview(effect)
        effect.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        for view in [effect, content] {
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor), view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class GlassLayer: NSView {
    let content = NSView()
    private let container: NSView
    override init(frame: NSRect) {
        if let type = NSClassFromString("NSGlassEffectContainerView") as? NSView.Type {
            let glass = type.init(frame: .zero)
            glass.setValue(content, forKey: "contentView"); glass.setValue(0, forKey: "spacing")
            container = glass
        } else { container = NSView(); container.addSubview(content) }
        super.init(frame: frame)
        addSubview(container)
        for view in [container, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor), view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point), hit !== self, hit !== container, hit !== content else { return nil }
        return hit
    }
}
