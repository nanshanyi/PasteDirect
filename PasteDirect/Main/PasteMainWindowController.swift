//
//  PasteMainWindowController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Cocoa
import Carbon

class PasteMainWindowController: NSWindowController, NSWindowDelegate {

    var mainVC: PasteMainViewController
    let mainWindow: PasteMainWindow
    var isVisable: Bool {
        mainWindow.isVisible
    }
    init() {
        mainVC = PasteMainViewController(NSScreen.main?.frame)
        mainWindow = PasteMainWindow()
        super.init(window: mainWindow)
        mainWindow.contentViewController = mainVC
        mainWindow.delegate = self
        mainWindow.styleMask = [.borderless, .fullSizeContentView]
        mainWindow.level = .statusBar
        mainWindow.hasShadow = false
        mainWindow.backgroundColor = .clear
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.type == .keyDown && event.keyCode == kVK_Escape {
                self.dismissWindow()
                return nil
            }
            return event
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func windowDidResignKey(_ notification: Notification) {
        dismissWindow()
    }
    
    func dismissWindow(completionHandler: (() -> Void)? = nil) {
        self.mainVC.vcDismiss {
            self.mainWindow.resignFirstResponder()
            self.mainWindow.setIsVisible(false)
            completionHandler?()
        }
    }
    
        
    public func show(in frame: NSRect?) {
        let origin = frame?.origin ?? NSPoint(x: 0, y: 0)
        mainVC.frame = frame ?? NSRect(x: 0, y: 0, width: 2000, height: 400)
        mainWindow.setFrameOrigin(origin)
        mainWindow.setIsVisible(true)
        mainWindow.becomeFirstResponder()
        NSApp.activate(ignoringOtherApps: true)
    }

}