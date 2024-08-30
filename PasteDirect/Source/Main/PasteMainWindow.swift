//
//  MyWindow.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Cocoa

final class PasteMainWindow: NSWindow {
    // 隐藏titlebar会导致window的BecomeKey 不调用
    override var canBecomeKey: Bool {
        return true
    }
}
