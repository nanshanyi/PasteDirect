//
//  PasteFilterItem.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/04/09.
//

import AppKit

final class PasteFilterItem: NSCollectionViewItem, UserInterfaceItemIdentifier {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hasIcon = false

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 6
        view = root

        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 28),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        view.addGestureRecognizer(click)

        updateAppearance()
    }

    private var labelLeading: NSLayoutConstraint?
    private var labelTrailing: NSLayoutConstraint?

    func configure(title: String, icon: NSImage?, isOn: Bool) {
        label.stringValue = title
        hasIcon = icon != nil
        iconView.image = icon
        iconView.isHidden = !hasIcon

        labelLeading?.isActive = false
        let leading: CGFloat = hasIcon ? 28 : 10
        labelLeading = label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leading)
        labelLeading?.isActive = true

        if labelTrailing == nil {
            labelTrailing = label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
            labelTrailing?.isActive = true
        }

        self.isSelected = isOn
        updateAppearance()
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    @objc private func tapped() {
        onClick?()
    }

    private func updateAppearance() {
        if isSelected {
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            label.textColor = .controlAccentColor
        } else {
            view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            label.textColor = .labelColor
        }
    }

    func fittingWidth() -> CGFloat {
        let textWidth = label.intrinsicContentSize.width
        return (hasIcon ? 28 : 10) + textWidth + 10
    }
}
