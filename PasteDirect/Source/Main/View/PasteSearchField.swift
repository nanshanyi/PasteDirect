//
//  SearchField.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/22.
//

import Cocoa
import Combine
import SnapKit

// MARK: - Custom Cell

final class PasteSearchFieldCell: NSSearchFieldCell {

    /// 标签占用的左侧宽度
    var extraLeadingOffset: CGFloat = 0
    /// 右侧 filterButton 占用的宽度
    var extraTrailingOffset: CGFloat = 28

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var r = super.searchTextRect(forBounds: rect)
        if extraLeadingOffset > 0 {
            r.origin.x += extraLeadingOffset
            r.size.width -= extraLeadingOffset
        }
        r.size.width -= extraTrailingOffset
        return r
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        var r = super.cancelButtonRect(forBounds: rect)
        r.origin.x = rect.width - extraTrailingOffset - r.width
        return r
    }
}

// MARK: - PasteSearchField

final class PasteSearchField: NSSearchField {
    var isEditing = false
    var isFirstResponder: Bool {
        currentEditor() != nil && currentEditor() == window?.firstResponder
    }

    @Published private(set) var text: String = ""

    let filterButton = NSButton().then {
        $0.isBordered = false
        $0.refusesFirstResponder = true
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let icon = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)
        $0.image = icon?.withSymbolConfiguration(config)
        $0.contentTintColor = .secondaryLabelColor
    }

    private let tagContainer = NSStackView().then {
        $0.orientation = .horizontal
        $0.spacing = 4
        $0.alignment = .centerY
    }

    private var tagViews: [NSView] = []
    var hasTags: Bool { !tagViews.isEmpty }

    private var customCell: PasteSearchFieldCell? {
        cell as? PasteSearchFieldCell
    }

    override class var cellClass: AnyClass? {
        get { PasteSearchFieldCell.self }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAccessories()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAccessories()
    }

    private func setupAccessories() {
        addSubview(tagContainer)
        addSubview(filterButton)

        tagContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(34)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
            make.trailing.lessThanOrEqualTo(filterButton.snp.leading).offset(-4)
        }

        filterButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-2)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(26)
        }
    }

    func updateTags(_ tags: [(text: String, icon: NSImage?)]) {
        tagViews.forEach { $0.removeFromSuperview() }
        tagViews.removeAll()
        tagContainer.arrangedSubviews.forEach { tagContainer.removeArrangedSubview($0); $0.removeFromSuperview() }

        for tag in tags {
            let pill = makeTagPill(tag.text, icon: tag.icon)
            tagContainer.addArrangedSubview(pill)
            tagViews.append(pill)
        }

        tagContainer.layoutSubtreeIfNeeded()
        let tagsWidth = tags.isEmpty ? 0 : tagContainer.frame.width + 2
        customCell?.extraLeadingOffset = tagsWidth

        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if let editor = currentEditor() as? NSTextView {
            let textRect = customCell?.searchTextRect(forBounds: bounds) ?? bounds
            if editor.frame != textRect {
                editor.frame = textRect
                editor.needsDisplay = true
            }
        }
    }

    override var stringValue: String {
        didSet {
            if stringValue != text {
                text = stringValue
            }
        }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        text = stringValue
    }

    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Tag Pill

    private func makeTagPill(_ text: String, icon: NSImage?) -> NSView {
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 4
        pill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY

        if let icon {
            let iv = NSImageView(image: icon)
            iv.imageScaling = .scaleProportionallyDown
            iv.snp.makeConstraints { $0.width.height.equalTo(14) }
            stack.addArrangedSubview(iv)
        }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .controlAccentColor
        label.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(label)

        pill.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(5)
            make.trailing.equalToSuperview().offset(-5)
            make.centerY.equalToSuperview()
        }

        pill.snp.makeConstraints { make in
            make.height.equalTo(20)
        }

        return pill
    }
}
