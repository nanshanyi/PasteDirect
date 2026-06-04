//
//  ImageBlobStore.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/06/04.
//

import Foundation

/// 图片原图的磁盘存储(actor)。
/// 把图片二进制从 SQLite BLOB 外置到独立文件 `~/Documents/paste/images/<hash>.bin`，
/// 数据库里只保留缩略图，原图按需从文件加载。
/// 文件名用原图内容哈希(PasteboardModel.hashValue)，与去重主键天然一致，同图只存一份。
actor ImageBlobStore {
    static let shared = ImageBlobStore()

    private let directory: URL

    /// - Parameter directory: 存储目录，默认 `~/Documents/paste/images`。测试可注入临时目录。
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = docDir.appendingPathComponent("paste/images", isDirectory: true)
        }
        createDirectoryIfNeeded()
    }

    private nonisolated func createDirectoryIfNeeded() {
        var isDir: ObjCBool = false
        let path = directory.path
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for hash: Int) -> URL {
        directory.appendingPathComponent("\(hash).bin", isDirectory: false)
    }

    /// 写入原图。已存在同 hash 文件则跳过(内容相同，省一次写)。
    func save(_ data: Data, for hash: Int) {
        let url = fileURL(for: hash)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log("ImageBlobStore save failed: \(error)")
        }
    }

    /// 按需加载原图。文件不存在或读取失败返回 nil(调用方负责降级)。
    func load(for hash: Int) -> Data? {
        let url = fileURL(for: hash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func exists(for hash: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: hash).path)
    }

    func delete(for hash: Int) {
        try? FileManager.default.removeItem(at: fileURL(for: hash))
    }

    /// 清空整个图片目录(配合 clearAllData)。
    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        createDirectoryIfNeeded()
    }
}
