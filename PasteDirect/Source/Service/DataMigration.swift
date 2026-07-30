//
//  DataMigration.swift
//  PasteDirect
//
//  一次性数据迁移：把沙盒容器内的数据从 Documents/ 平移到语义正确的
//  Application Support/。历史版本把数据库/图片/忽略名单错误地放在容器的
//  Documents 子目录下，现规整到 Application Support。
//
//  仅在容器内部移动，不涉及跨沙盒边界，无需额外权限。
//

import Foundation

enum DataMigration {
    /// 迁移完成标记，避免重复执行。
    private static let migrationKey = "didMigrateDocumentsToAppSupport_v1"

    /// 需要迁移的条目：相对各自 search-path 根目录的子路径。
    /// paste/ 下含 paste.sqlite3 与 images/；appItems.json 在根目录。
    private static let items = ["paste", "appItems.json"]

    /// 把旧的 Documents 数据移动到 Application Support。
    /// 必须在任何存储组件（PasteSQLManager / ImageBlobStore / IgnoredAppsManager）
    /// 初始化之前同步调用，否则新目录会被提前建出、迁移条件失效。
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let fm = FileManager.default
        guard let oldRoot = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let newRoot = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        // 确保目标根目录存在（Application Support 首次可能不存在）。
        try? fm.createDirectory(at: newRoot, withIntermediateDirectories: true)

        for item in items {
            let src = oldRoot.appendingPathComponent(item)
            let dst = newRoot.appendingPathComponent(item)
            // 源不存在（全新安装）或目标已存在（不覆盖用户新数据）时跳过。
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.moveItem(at: src, to: dst)
                Log("DataMigration moved \(item) to Application Support")
            } catch {
                Log("DataMigration failed for \(item): \(error)")
            }
        }

        defaults.set(true, forKey: migrationKey)
    }
}
