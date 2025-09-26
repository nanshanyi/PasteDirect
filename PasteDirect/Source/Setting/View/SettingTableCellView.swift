//
//  SettingTable.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/23.
//

import Cocoa
import SnapKit

class SettingTableCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = PasteIgnoreListCellView.identifier
        initSubviews()
    }
    
    init() {
        super.init(frame: .zero)
        identifier = PasteIgnoreListCellView.identifier
        initSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private lazy var text = NSTextField().then {
        $0.isBordered = false
        $0.isEditable = false
        $0.backgroundColor = .clear
        $0.font = NSFont.systemFont(ofSize: 13)
    }
    
    private lazy var image = NSImageView().then {
        $0.imageScaling = .scaleProportionallyUpOrDown
    }
    
    func initSubviews() {
        addSubview(text)
        addSubview(image)
        
        text.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(image.snp.trailing).offset(8)
            make.trailing.equalToSuperview().offset(-12)
        }
        image.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalToSuperview().offset(12)
            make.width.height.equalTo(16)
        }
//        // 设置约束
//        NSLayoutConstraint.activate([
//            imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 12),
//            imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
//            imageView.widthAnchor.constraint(equalToConstant: 16),
//            imageView.heightAnchor.constraint(equalToConstant: 16),
//            
//            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
//            textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
//            textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -12)
//        ])
    }
    
    func configcell(_ item: PreferenceItem) {
        text.stringValue = item.title
        image.image = item.icon
    }
}

extension SettingTableCellView: UserInterfaceItemIdentifier {}

