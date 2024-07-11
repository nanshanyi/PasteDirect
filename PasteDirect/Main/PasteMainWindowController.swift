//
//  PasteMainWindowController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Carbon
import Cocoa

class PasteMainWindowController: NSWindowController {
    var isVisable: Bool { window?.isVisible ?? false }

    init() {
        let window = PasteMainWindow(contentViewController: PasteMainViewController())
        super.init(window: window)
        setUpWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpWindow() {
        window?.delegate = self
        window?.styleMask = [.borderless, .fullSizeContentView]
        window?.level = .statusBar
        window?.hasShadow = false
        window?.backgroundColor = .clear
    }

    func dismissWindow(completionHandler: (() -> Void)? = nil) {
        let mainViewController = window?.contentViewController as? PasteMainViewController
        mainViewController?.dismissVC { [weak self] in
            self?.window?.resignFirstResponder()
            self?.window?.setIsVisible(false)
            completionHandler?()
        }
    }

    func show(in frame: NSRect?) {
        let frame = frame ?? .zero
        window?.setFrame(frame, display: true)
        window?.setIsVisible(true)
        window?.becomeFirstResponder()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

extension PasteMainWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        #if !DEBUG
            dismissWindow()
        #endif
    }
}
