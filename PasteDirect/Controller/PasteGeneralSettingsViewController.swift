//
//  PasteGeneralSettingsViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/14.
//

import Cocoa
import Preferences
import ServiceManagement
import RxSwift

class PasteGeneralSettingsViewController: NSViewController, SettingsPane {
    let preferencePaneIdentifier = Settings.PaneIdentifier.general
    
    let preferencePaneTitle = "通用"
    override var nibName: NSNib.Name? { "PasteGeneralSettingsViewController" }
    let prefs = UserDefaults.standard
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
        pasteOnlyTextButton.state = prefs.bool(forKey: PrefKey.pasteOnlyText.rawValue) ? .on : .off
        pasteDirectButton.state = prefs.bool(forKey: PrefKey.pasteDirect.rawValue) ? .on : .off
        historySlider.integerValue = prefs.integer(forKey: PrefKey.historyTime.rawValue)
        clearInfoLabel.isHidden = true
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        clearInfoLabel.isHidden = true
    }
    
    private func initRx() {
        PasteDataStore.main.totoalCount
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
        prefs.set(isOn, forKey: PrefKey.pasteDirect.rawValue)
    }
    @IBAction func pasteOnlyText(_ sender: NSButton) {
        let isOn = sender.state == .on
        prefs.set(isOn, forKey: PrefKey.pasteOnlyText.rawValue)
    }
    @IBAction func clearAll(_ sender: NSButton) {
        PasteDataStore.main.clearAllData()
        prefs.set(nil, forKey: PrefKey.appColorData.rawValue)
        clearInfoLabel.isHidden = false
    }
    
    @IBAction func sliderChange(_ sender: NSSlider) {
        let current = prefs.integer(forKey: PrefKey.historyTime.rawValue)
        if sender.integerValue < current {
            let alert = NSAlert()
            alert.messageText = "剪贴板的内容数量已经超过预设，要删除旧的条目来减少容量吗？"
            alert.informativeText = "该动作将无法被撤销"
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: self.view.window!) { res in
                if res == .alertFirstButtonReturn, let type = HistoryTime(rawValue: sender.integerValue) {
                    PasteDataStore.main.clearData(for: type)
                    UserDefaults.standard.set(sender.integerValue, forKey: PrefKey.historyTime.rawValue)
                } else if res == .alertSecondButtonReturn {
                    sender.integerValue = current
                }
            }
        } else {
            UserDefaults.standard.set(sender.integerValue, forKey: PrefKey.historyTime.rawValue)
        }
    }
    
    func setStartAtLogin(enabled: Bool) {
      let identifier = "\(Bundle.main.bundleIdentifier!)Helper" as CFString
      SMLoginItemSetEnabled(identifier, enabled)
    }
}
