//
//  PasteIgnoreListCellView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/8.
//

import Cocoa

protocol PasteIgnoreListCellViewDelegate: AnyObject {
    func deleteItem(_ item: PasteIgnoreListItem)
}

final class PasteIgnoreListCellView: NSTableCellView {
    weak var delegate: PasteIgnoreListCellViewDelegate?
    private var item: PasteIgnoreListItem?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = PasteIgnoreListCellView.identifier
        initSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private lazy var textView = NSTextField().then {
        $0.isEditable = false
        $0.isBordered = false
        $0.isBezeled = false
        $0.drawsBackground = false
        $0.font = NSFont.systemFont(ofSize: 14)
        $0.textColor = NSColor.labelColor
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private lazy var deleteButton = NSButton().then {
        $0.bezelColor = .controlAccentColor
        $0.title = "删除"
        $0.bezelStyle = .rounded
        $0.target = self
        $0.action = #selector(deleteButtonClick)
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
    
}

extension PasteIgnoreListCellView {
    
    func updateData(_ item: PasteIgnoreListItem) {
        self.item = item
        textView.stringValue = item.id
        deleteButton.isHidden = item.type == .default
    }
    
    private func initSubviews() {
        addSubview(textView)
        addSubview(deleteButton)
        textView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        deleteButton.snp.makeConstraints { make in
            make.width.equalTo(40)
            make.height.equalTo(20)
            make.centerY.equalTo(textView)
            make.trailing.equalTo(self).offset(-12)
            make.leading.equalTo(textView.snp.trailing).offset(20)
        }
    }
    
    @objc private func deleteButtonClick() {
        guard let item = item else { return }
        delegate?.deleteItem(item)
    }
}

extension PasteIgnoreListCellView: UserInterfaceItemIdentifier {}
