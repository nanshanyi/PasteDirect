//
//  File.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/30.
//

import AppKit

actor ColorCache {
    private var cache = [Int: NSColor?]()
    private var ongoingTasks = [Int: Task<NSColor?, Never>]()
    
    @discardableResult
    func getOrExtract(for model: PasteboardModel) async -> NSColor? {
        let key = model.appPath.hashValue
        
        if let color = cache[key] { return color }
        
        if let existingTask = ongoingTasks[key] {
            return await existingTask.value
        }
        
        let task = Task<NSColor?, Never> {
            let icon = NSWorkspace.shared.icon(forFile: model.appPath)
            return await ImageColorExtractor.extractAverageColor(from: icon)
        }
        
        ongoingTasks[key] = task
        let color = await task.value
        ongoingTasks.removeValue(forKey: key)
        cache[key] = color
        
        return color
    }
}
