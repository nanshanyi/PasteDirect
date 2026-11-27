//
//  UpdateCoordinator.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/05/09.
//

import AppKit
import Combine
import Sparkle

/// 基于 Sparkle 的自动更新门面：
/// - 检查时机（启动 + 周期性）由 Sparkle 的自动检查管理，About 页开关映射 SUEnableAutomaticChecks
/// - "自动下载更新"开关映射 SUAutomaticallyUpdate（前提是自动检查开启，Sparkle 自身有此约束）
/// - 下载、签名校验、安装、重启全部由 Sparkle 标准用户驱动完成
@MainActor
final class UpdateCoordinator: NSObject, ObservableObject {
    static let shared = UpdateCoordinator()

    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = false

    private var updaterController: SPUStandardUpdaterController?

    private override init() {
        Self.migrateLegacySettings()
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        automaticallyDownloadsUpdates = UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") as? Bool ?? false
        super.init()
    }

    /// applicationDidFinishLaunching 时调用
    func startup() {
        guard updaterController == nil else { return }

        guard hasValidPublicKey else {
            Log("Sparkle 公钥尚未配置，暂不启动更新器；请将 generate_keys 输出的 SUPublicEDKey 填入 Info.plist")
            return
        }

        // 先配置动态开关，再启动 Sparkle，避免启动周期读取到旧值。
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates && automaticallyChecksForUpdates
        updaterController = controller

#if DEBUG
        // 开发构建不做后台自动检查；手动“检查更新”仍可用。
        controller.updater.automaticallyChecksForUpdates = false
        automaticallyChecksForUpdates = false
#endif
        controller.startUpdater()
    }

    /// 手动触发检查（状态栏菜单 / About 页）
    func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        updaterController?.updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            setAutomaticallyDownloadsUpdates(false)
        }
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        let value = enabled && automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = value
        updaterController?.updater.automaticallyDownloadsUpdates = value
    }

    /// v3.5.x 旧设置迁移：autoCheckUpdate → SUEnableAutomaticChecks、ignoredUpdateVersion → SUSkippedVersion。
    /// 显式写入 SUEnableAutomaticChecks 后，Sparkle 不会再弹自动检查授权询问。
    private static func migrateLegacySettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let legacyAutoCheck = defaults.object(forKey: "autoCheckUpdate") as? Bool {
            defaults.set(legacyAutoCheck, forKey: "SUEnableAutomaticChecks")
        }
        if defaults.object(forKey: "SUSkippedVersion") == nil,
           let legacyIgnored = defaults.string(forKey: "ignoredUpdateVersion"), !legacyIgnored.isEmpty {
            defaults.set(legacyIgnored, forKey: "SUSkippedVersion")
        }
        defaults.removeObject(forKey: "autoCheckUpdate")
        defaults.removeObject(forKey: "ignoredUpdateVersion")
    }

    private var hasValidPublicKey: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let data = Data(base64Encoded: value),
              data.count == 32 else {
            return false
        }
        return true
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateCoordinator: SPUUpdaterDelegate {
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log("未发现新版本")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log("发现新版本: \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        Log("更新包下载失败: \(error.localizedDescription)")
    }
}
