//
//  SearchField.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/22.
//

import Cocoa
import Combine
import SnapKit

final class PasteSearchField: NSView {

    // MARK: - Public API

    weak var delegate: NSSearchFieldDelegate?

    @Published private(set) var text: String = ""

    var stringValue: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            if text != newValue { text = newValue }
            updateCancelButton()
        }
    }

    var placeholderString: String? {
        get { textField.placeholderString }
        set { textField.placeholderString = newValue }
    }

    var isFirstResponder: Bool {
        guard let editor = textField.currentEditor() else { return false }
        return editor === window?.firstResponder
    }

    var hasTags: Bool { !tagViews.isEmpty }

    let filterButton = NSButton().then {
        $0.isBordered = false
        $0.refusesFirstResponder = true
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let icon = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)
        $0.image = icon?.withSymbolConfiguration(config)
        $0.contentTintColor = .secondaryLabelColor
    }

    // MARK: - Subviews

    private let searchIcon = NSImageView().then {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let icon = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        $0.image = icon?.withSymbolConfiguration(config)
        $0.contentTintColor = .secondaryLabelColor
        $0.imageScaling = .scaleProportionallyDown
    }

    private let tagContainer = NSStackView().then {
        $0.orientation = .horizontal
        $0.spacing = 4
        $0.alignment = .centerY
    }

    private lazy var textField = NSTextField().then {
        $0.isBordered = false
        $0.drawsBackground = false
        $0.focusRingType = .none
        $0.font = .systemFont(ofSize: 13)
        $0.textColor = .labelColor
        $0.isEditable = true
        $0.isSelectable = true
        $0.cell?.usesSingleLineMode = true
        $0.cell?.lineBreakMode = .byTruncatingTail
        $0.cell?.wraps = false
        $0.cell?.isScrollable = true
        $0.delegate = self
    }

    private lazy var cancelButton = NSButton().then {
        $0.isBordered = false
        $0.refusesFirstResponder = true
        $0.bezelStyle = .regularSquare
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let icon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        $0.image = icon?.withSymbolConfiguration(config)
        $0.contentTintColor = .secondaryLabelColor
        $0.isHidden = true
        $0.target = self
        $0.action = #selector(clearText)
    }

    private var tagViews: [NSView] = []
    private var isFocused = false { didSet { updateBorderAppearance() } }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.masksToBounds = true
        updateBorderAppearance()
        updateBackgroundColor()

        addSubview(searchIcon)
        addSubview(tagContainer)
        addSubview(textField)
        addSubview(cancelButton)
        addSubview(filterButton)

        searchIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(14)
        }

        tagContainer.snp.makeConstraints { make in
            make.leading.equalTo(searchIcon.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
            make.height.equalTo(18)
        }

        filterButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-6)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(22)
        }

        cancelButton.snp.makeConstraints { make in
            make.trailing.equalTo(filterButton.snp.leading).offset(-2)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(14)
        }

        textField.snp.makeConstraints { make in
            make.leading.equalTo(tagContainer.snp.trailing).offset(4)
            make.trailing.equalTo(cancelButton.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
        }

        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tagContainer.setContentHuggingPriority(.required, for: .horizontal)
        tagContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(textField) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let leading = searchIcon.frame.maxX
        let trailing = cancelButton.isHidden ? filterButton.frame.minX : cancelButton.frame.minX
        guard point.x >= leading, point.x <= trailing else {
            super.mouseDown(with: event)
            return
        }
        if window?.firstResponder !== textField.currentEditor() {
            window?.makeFirstResponder(textField)
        }
    }

    override func resetCursorRects() {
        let leading = searchIcon.frame.maxX
        let trailing = cancelButton.isHidden ? filterButton.frame.minX : cancelButton.frame.minX
        let rect = NSRect(x: leading, y: 0, width: max(0, trailing - leading), height: bounds.height)
        addCursorRect(rect, cursor: .iBeam)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderAppearance()
        updateBackgroundColor()
    }

    private func updateBorderAppearance() {
        layer?.borderWidth = isFocused ? 2 : 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = isFocused
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
        }
    }

    private func updateBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        }
    }

    // MARK: - Tags

    func updateTags(_ tags: [(text: String, icon: NSImage?)]) {
        tagViews.forEach { $0.removeFromSuperview() }
        tagViews.removeAll()
        tagContainer.arrangedSubviews.forEach {
            tagContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for tag in tags {
            let pill = makeTagPill(tag.text, icon: tag.icon)
            tagContainer.addArrangedSubview(pill)
            tagViews.append(pill)
        }

        placeholderString = tags.isEmpty ? String(localized: "Search") : ""
        needsLayout = true
    }

    // MARK: - Actions

    @objc private func clearText() {
        stringValue = ""
        window?.makeFirstResponder(textField)
    }

    private func updateCancelButton() {
        cancelButton.isHidden = text.isEmpty
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Tag Pill

    private func makeTagPill(_ text: String, icon: NSImage?) -> NSView {
        let pill = TagPillView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 4
        pill.updateBackground()

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
            make.height.equalTo(18)
        }

        return pill
    }
}

// MARK: - TagPillView

private final class TagPillView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        }
    }
}

// MARK: - NSTextFieldDelegate

extension PasteSearchField: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        isFocused = true
    }

    func controlTextDidChange(_ obj: Notification) {
        text = textField.stringValue
        updateCancelButton()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        isFocused = false
        delegate?.controlTextDidEndEditing?(obj)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        delegate?.control?(control, textView: textView, doCommandBy: commandSelector) ?? false
    }
}
