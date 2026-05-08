//
//  PasteEmptyStateView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/05/08.
//

import Cocoa
import SnapKit

final class PasteEmptyStateView: NSView {

    enum Mode {
        case noHistory
        case noResults
    }

    private let iconView = NSImageView().then {
        $0.imageScaling = .scaleProportionallyDown
        $0.contentTintColor = .tertiaryLabelColor
    }

    private let titleLabel = NSTextField(labelWithString: "").then {
        $0.font = .systemFont(ofSize: 15, weight: .medium)
        $0.textColor = .secondaryLabelColor
        $0.alignment = .center
    }

    private let subtitleLabel = NSTextField(labelWithString: "").then {
        $0.font = .systemFont(ofSize: 12)
        $0.textColor = .tertiaryLabelColor
        $0.alignment = .center
    }

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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(14, after: iconView)
        stack.setCustomSpacing(4, after: titleLabel)

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().offset(-24)
        }

        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(44)
        }
    }

    func configure(_ mode: Mode) {
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        switch mode {
        case .noHistory:
            iconView.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            titleLabel.stringValue = String(localized: "No clipboard history yet")
            subtitleLabel.stringValue = String(localized: "Copy anything to get started")
        case .noResults:
            iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            titleLabel.stringValue = String(localized: "No results")
            subtitleLabel.stringValue = String(localized: "Try a different keyword or filter")
        }
    }
}
