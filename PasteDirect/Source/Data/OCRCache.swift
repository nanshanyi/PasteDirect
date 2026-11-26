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
    private enum CacheEntry {
        case none
        case text(String)
    }

    private var cache = [Int: CacheEntry]()
    private var ongoingTasks = [Int: Task<OCRResult, Never>]()

    @discardableResult
    func getOrExtract(for model: PasteboardModel) async -> String? {
        let key = model.hashValue

        if let cached = cache[key] {
            switch cached {
            case .none:
                return nil
            case .text(let text):
                return text
            }
        }

        if let existing = ongoingTasks[key] {
            if case .text(let text) = await existing.value { return text }
            return nil
        }

        // 直接把原始图片 Data 交给后台线程,在解码阶段降采样后识别(省一次全尺寸 NSImage 构造)
        let task = Task<OCRResult, Never> { [data = model.data] in
            await Task.detached(priority: .userInitiated) {
                ImageOCRExtractor.extractText(from: data)
            }.value
        }

        ongoingTasks[key] = task
        let result = await task.value
        ongoingTasks.removeValue(forKey: key)

        switch result {
        case .text(let text):
            cache[key] = .text(text)
            return text
        case .empty:
            cache[key] = CacheEntry.none
            return nil
        case .failed:
            // 偶发失败不缓存,允许下次重试
            return nil
        }
    }
}
