//
//  UpdateCoordinator.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/05/09.
//

import AppKit

@MainActor
final class UpdateCoordinator {
    static let shared = UpdateCoordinator()

    private var isChecking = false

    private init() {}

    /// 启动时自动检查:尊重"自动检查"开关与"忽略版本"
    func checkSilently() {
        guard PasteUserDefaults.autoCheckUpdate else { return }
        Task { await run(manual: false) }
    }

    /// 手动触发:忽略开关与忽略版本,无更新也要提示
    func checkManually() {
        Task { await run(manual: true) }
    }

    private func run(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let result = try await UpdateChecker.check()
            switch result {
            case .upToDate:
                if manual { presentUpToDate() }
            case .newer(let release):
                if !manual, PasteUserDefaults.ignoredUpdateVersion == release.version {
                    return
                }
                presentNewVersion(release, manual: manual)
            }
        } catch {
            if manual { presentError(error) }
        }
    }

    // MARK: - Alerts

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = String(localized: "You're up to date")
        alert.informativeText = String(localized: "PasteDirect \(UpdateChecker.currentVersion()) is the latest version.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func presentNewVersion(_ release: AppRelease, manual: Bool) {
        let alert = NSAlert()
        alert.messageText = String(localized: "A new version is available")
        let current = UpdateChecker.currentVersion()
        let summary = String(localized: "PasteDirect \(release.version) is available — you have \(current).")
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = notes.isEmpty ? summary : "\(summary)\n\n\(notes)"
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))
        if !manual {
            alert.addButton(withTitle: String(localized: "Skip this version"))
        }

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        case .alertThirdButtonReturn where !manual:
            PasteUserDefaults.ignoredUpdateVersion = release.version
        default:
            break
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Unable to check for updates")
        alert.informativeText = String(localized: "Please check your network connection and try again.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
