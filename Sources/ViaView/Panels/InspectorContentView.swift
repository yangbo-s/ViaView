import AppKit

/// A scrollable inspector body with a stable action row, shared by both tools.
final class InspectorContentView: NSView {
    let scroll = NSScrollView()
    let stack = NSStackView()
    let footer = NSStackView()
    private let divider = NSBox()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let document = FlippedDocument()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        footer.spacing = 8
        footer.alignment = .centerY
        divider.boxType = .separator
        document.addSubview(stack)
        [scroll, divider, footer].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func clear() {
        for group in [stack, footer] {
            for view in group.arrangedSubviews { group.removeArrangedSubview(view); view.removeFromSuperview() }
        }
    }
    func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    var preferredHeight: CGFloat { max(220, stack.fittingSize.height + 86) }
}

func inspectorRow(_ name: String, value: String) -> NSView {
    let title = label(name, size: 11, color: .secondaryLabelColor)
    let text = label(value, size: 12)
    text.isSelectable = true
    text.alignment = .right
    text.maximumNumberOfLines = 3
    text.lineBreakMode = .byWordWrapping
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    title.widthAnchor.constraint(equalToConstant: 84).isActive = true
    let row = NSStackView(views: [title, text])
    row.alignment = .firstBaseline
    row.spacing = 12
    return row
}

func inspectorSection(_ title: String, views: [NSView]) -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    let heading = label(title, size: 12, weight: .semibold)
    stack.addArrangedSubview(heading)
    for view in views {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    return stack
}

func inspectorSeparator() -> NSBox {
    let line = NSBox()
    line.boxType = .separator
    return line
}
