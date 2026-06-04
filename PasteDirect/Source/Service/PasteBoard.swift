//
//  PasteBoard.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation

/// 在专用后台队列上轮询 `NSPasteboard.changeCount`，检测到变化时回调（携带新的 changeCount）。
/// macOS 没有剪贴板变化通知 API，所有剪贴板工具都靠轮询 changeCount；这里用 DispatchSourceTimer
/// 跑在后台 queue：高频空转的比对不占用主线程，且 leeway 让系统合并唤醒以省电。
/// 可变状态只在 `queue` 上访问（`lastSeenChangeCount` 仅由 init 赋初值、其后只在 tick 内修改），
/// 故标记 `@unchecked Sendable`。
private final class PasteboardWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pastedirect.pasteboard.monitor", qos: .utility)
    private let interval: TimeInterval
    private let onChange: @Sendable (Int) -> Void
    private var timer: DispatchSourceTimer?
    private var lastSeenChangeCount: Int

    init(interval: TimeInterval, onChange: @escaping @Sendable (Int) -> Void) {
        self.interval = interval
        self.onChange = onChange
        self.lastSeenChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        let current = NSPasteboard.general.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current
        onChange(current)
    }
}

@MainActor
final class PasteBoard {
    static let main = PasteBoard()

    private let pasteboard = NSPasteboard.general
    private let pollInterval = 0.5
    private var watcher: PasteboardWatcher?
    /// 记录我们自己写入剪贴板时的 changeCount，监听检测到该变化时跳过，避免把自己粘贴的内容重复入库
    private var selfWriteChangeCount = -1

    func startListening() {
        let watcher = PasteboardWatcher(interval: pollInterval) { [weak self] _ in
            // 后台 queue 回调：仅在 changeCount 变化时触发，跳回主线程读取内容
            Task { @MainActor in
                self?.handlePasteboardChange()
            }
        }
        self.watcher = watcher
        watcher.start()
    }

    private func handlePasteboardChange() {
        // 读取当前最新 changeCount 比对。pasteData 在主线程同步执行，本方法（主线程 Task）
        // 必然在其完全结束后才运行，故能稳定读到自产写入的最终 changeCount 并跳过，
        // 不受后台 watcher 在 clearContents/setData 之间观察到中间值的影响。
        guard pasteboard.changeCount != selfWriteChangeCount else { return }
        guard let item = pasteboard.pasteboardItems?.first else { return }
        PasteDataStore.main.addNewItem(item)
    }

    func pasteData(_ data: PasteboardModel?, _ isOriginal: Bool = false) {
        guard let data else { return }
        let updated = data.withUpdatedDate()
        PasteDataStore.main.insertModel(updated)
        pasteboard.clearContents()
        if updated.type == .string, !isOriginal {
            pasteboard.setString(updated.dataString, forType: .string)
        } else if updated.type == .color {
            let string = isOriginal ? updated.dataString : updated.hexColorString
            pasteboard.setString(string ?? updated.dataString, forType: .string)
        } else {
            pasteboard.setData(updated.data, forType: updated.pasteboardType)
        }
        // 写入完成后记录最终 changeCount。pasteData 全程同步执行（无 await），
        // 后台 watcher 只可能观察到这个最终值，handlePasteboardChange 据此跳过自产变化。
        selfWriteChangeCount = pasteboard.changeCount
    }
}
