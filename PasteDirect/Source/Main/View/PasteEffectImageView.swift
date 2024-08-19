//
//  PasteEffectImageView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import AppKit
import SnapKit

final class PasteEffectImageView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var image: NSImage? {
        didSet {
            imageView.image = image
        }
    }
    
    private lazy var imageView = NSImageView().then {
        $0.imageScaling = .scaleAxesIndependently
    }
    
    private lazy var effectView = NSVisualEffectView().then {
        $0.blendingMode = .withinWindow
        $0.isEmphasized = true
        $0.state = .active
    }
    
    private func initSubviews() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        addSubview(imageView)
        addSubview(effectView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        effectView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
