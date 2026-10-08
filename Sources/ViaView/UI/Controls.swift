import AppKit

func symbolButton(_ symbol: String, _ title: String, target: AnyObject?, action: Selector, size: CGFloat = 36) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: target, action: action)
    button.bezelStyle = .texturedRounded; button.isBordered = false
    button.contentTintColor = .labelColor; button.toolTip = title; button.setAccessibilityLabel(title)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: size), button.heightAnchor.constraint(equalToConstant: size)])
    return button
}

func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle; return field
}
