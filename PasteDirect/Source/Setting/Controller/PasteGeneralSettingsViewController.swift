//
//  PasteGeneralSettingsViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/14.
//

import Cocoa
import Settings
import ServiceManagement
import RxSwift

final class PasteGeneralSettingsViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.general
    let paneTitle = "通用"
    override var nibName: NSNib.Name? { "PasteGeneralSettingsViewController" }
    let disposeBag = DisposeBag()
    @IBOutlet weak var onStartButton: NSButton!
    
    @IBOutlet weak var pasteOnlyTextButton: NSButton!
    @IBOutlet weak var pasteDirectButton: NSButton!
    
    @IBOutlet weak var clearAllButton: NSButton!
    @IBOutlet weak var historySlider: NSSlider!
    
    @IBOutlet weak var totalLabel: NSTextField!
    @IBOutlet weak var clearInfoLabel: NSTextField!
    
    var toolbarItemIcon: NSImage {
        NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil)!
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initRx()
        onStartButton.state = LaunchAtLogin.isEnabled ? .on : .off
        pasteOnlyTextButton.state = PasteUserDefaults.pasteOnlyText ? .on : .off
        pasteDirectButton.state = PasteUserDefaults.pasteDirect ? .on : .off
        historySlider.integerValue = PasteUserDefaults.historyTime
        clearInfoLabel.isHidden = true
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        clearInfoLabel.isHidden = true
    }
    
    private func initRx() {
        PasteDataStore.main.totoalCount
            .observe(on: MainScheduler.instance)
            .subscribe(
                with: self,
                onNext: { wrapper, value in
                    wrapper.totalLabel.stringValue = "\(value)条"
                })
            .disposed(by: disposeBag)
    }
    
    @IBAction func onMacStart(_ sender: NSButton) {
        let isOn = sender.state == .on
        LaunchAtLogin.isEnabled = isOn
    }
    @IBAction func pasteDirect(_ sender: NSButton) {
        let isOn = sender.state == .on
        PasteUserDefaults.pasteDirect = isOn
    }
    @IBAction func pasteOnlyText(_ sender: NSButton) {
        let isOn = sender.state == .on
        PasteUserDefaults.pasteOnlyText = isOn
    }
    @IBAction func clearAll(_ sender: NSButton) {
        PasteDataStore.main.clearAllData()
        PasteUserDefaults.appColorData = [:]
        clearInfoLabel.isHidden = false
    }
    
    @IBAction func sliderChange(_ sender: NSSlider) {
        let current = PasteUserDefaults.historyTime
        if sender.integerValue < current {
            let alert = NSAlert()
            alert.messageText = "剪贴板的内容数量已经超过预设，要删除旧的条目来减少容量吗？"
            alert.informativeText = "该动作将无法被撤销"
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: self.view.window!) { res in
                if res == .alertFirstButtonReturn, let type = HistoryTime(rawValue: sender.integerValue) {
                    PasteDataStore.main.clearData(for: type)
                    PasteUserDefaults.historyTime = sender.integerValue
                } else if res == .alertSecondButtonReturn {
                    sender.integerValue = current
                }
            }
        } else {
            PasteUserDefaults.historyTime = sender.integerValue
        }
    }
}
