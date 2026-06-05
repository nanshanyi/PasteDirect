//
//  OCRCache.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/05/30.
//

import Foundation

/// OCR 识别结果缓存(actor),镜像 ColorCache 的合并并发模式
/// key 用 PasteboardModel.hashValue(图片数据 hash),同一张图多次复制只识别一次
actor OCRCache {
    private var cache = [Int: String?]()
    private var ongoingTasks = [Int: Task<String?, Never>]()

    @discardableResult
    func getOrExtract(for model: PasteboardModel) async -> String? {
        let key = model.hashValue

        if let cached = cache[key] { return cached }

        if let existing = ongoingTasks[key] {
            return await existing.value
        }

        // 直接把原始图片 Data 交给后台线程,在解码阶段降采样后识别(省一次全尺寸 NSImage 构造)
        let task = Task<String?, Never> { [data = model.data] in
            await Task.detached(priority: .userInitiated) {
                ImageOCRExtractor.extractText(from: data)
            }.value
        }

        ongoingTasks[key] = task
        let result = await task.value
        ongoingTasks.removeValue(forKey: key)
        cache[key] = result
        return result
    }
}
