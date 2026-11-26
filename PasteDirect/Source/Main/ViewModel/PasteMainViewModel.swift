//
//  PasteMainViewModel.swift
//  PasteDirect
//
//  Created by 南山忆 on 2022/10/20.
//

import AppKit
import Combine
import KeyboardShortcuts

@MainActor
final class PasteMainViewModel {
    // MARK: - 输出状态

    private(set) var items: [PasteboardModel] = []
    var selectedIndexPath = IndexPath(item: 0, section: 0)
    @Published private(set) var canLoadMore = false

    /// 列表更新事件。列表本身由 diffable 数据源按 hash 计算差异，这里只带额外信息。
    struct ListUpdate {
        /// 内容有变化、需要重新配置卡片的条目 hash
        var reloaded: [Int] = []
        /// 只有置顶状态变化的条目：只刷新图钉，不重配整张卡片（避免闪烁）
        var pinChanged: [PasteboardModel] = []
        var animated = false
        var scrollToBeginning = false
        /// 选中的条目已不在列表里（被删），需要把新的选中项滚到可见
        var scrollToSelection = false
        /// 由数据库内容变化引起（而不是翻页、搜索），类型计数需要重新统计
        var dataChanged = false
    }

    let listUpdate = PassthroughSubject<ListUpdate, Never>()

    // MARK: - 筛选状态

    var filterState = FilterState.empty
    var filterIsActive: Bool { filterState.isActive }

    // MARK: - Private

    private let store = PasteDataStore.main
    private var cancellables = Set<AnyCancellable>()
    /// 当前列表对应的查询条件
    private var keyword = ""
    private var queryState = FilterState.empty
    /// 已加载部分最后一条的位置，下一页从它之后查
    private var cursor: PageCursor?
    private var hasMore = true
    private var isLoading = false { didSet { updateCanLoadMore() } }
    private var isVisible = false
    /// 每次发起新查询时递增，晚到的旧结果直接丢弃
    private var generation = 0
    private var fetchTask: Task<Void, Never>?
    /// 用户删除后要补页。在收到删除信号时才设（此时数据库已删完），之后完成的那次刷新必然反映了这次删除，
    /// 由它来消费；删除那次刷新被后来的变化抢先时，交给抢先的那次补页。
    /// 只给删除用：取消置顶等变化也会让已加载范围变短，但不该顺手多加载一页
    private var refillAfterRefresh = false

    init() {
        store.didChange
            .sink { [weak self] change in self?.handleStoreChange(change) }
            .store(in: &cancellables)
    }
}

// MARK: - 列表加载

extension PasteMainViewModel {
    /// 加载首页。由界面在订阅 listUpdate 之后调用，保证第一次结果不会因为还没人订阅而丢掉
    func start() {
        reload()
    }

    private func updateCanLoadMore() {
        canLoadMore = hasMore && !isLoading
    }

    /// 按查询条件从第一页重新加载
    private func reload(keyword: String = "", state: FilterState = .empty) {
        self.keyword = keyword
        queryState = state
        refillAfterRefresh = false
        generation += 1
        let gen = generation
        fetchTask?.cancel()
        isLoading = true
        fetchTask = Task {
            let page = await store.fetchPage(keyword: keyword, state: state, after: nil)
            guard gen == generation else { return }
            cursor = page.cursor
            hasMore = page.hasMore
            isLoading = false
            apply(page.items, animated: false, scrollToBeginning: true)
        }
    }

    func loadNextPage() {
        guard hasMore, !isLoading, let cursor else { return }
        let gen = generation
        isLoading = true
        fetchTask = Task {
            let page = await store.fetchPage(keyword: keyword, state: queryState, after: cursor)
            guard gen == generation else { return }
            hasMore = page.hasMore
            if let next = page.cursor { self.cursor = next }
            isLoading = false
            apply(items + page.items, animated: false)
        }
    }

    /// 数据库变化后，按当前查询条件重新取已加载的范围（到 cursor 为止），列表变成数据库里的真实顺序。
    /// 被移到 cursor 之后的条目（如取消置顶）会从已加载范围消失，翻页时再出现。
    private func refreshLoaded() {
        // 列表还是空的：没有范围可言，直接重取第一页
        guard let bound = cursor else {
            reload(keyword: keyword, state: queryState)
            return
        }
        generation += 1
        let gen = generation
        fetchTask?.cancel()
        isLoading = true
        let wasComplete = !hasMore
        fetchTask = Task {
            var list = await store.fetchThrough(keyword: keyword, state: queryState, cursor: bound)
            var nextCursor = bound
            var more = true
            if wasComplete {
                // 已经全部加载完时不会再翻页，cursor 之后多出来的条目（如取消置顶落到末尾）要在这里接住。
                // 只多取一页，单次刷新的量不随历史总数增长
                let tail = await store.fetchPage(keyword: keyword, state: queryState, after: bound)
                list += tail.items
                nextCursor = tail.cursor ?? bound
                more = tail.hasMore
            }
            guard gen == generation else { return }
            cursor = nextCursor
            hasMore = more
            isLoading = false
            apply(list, animated: true, dataChanged: true)
            // 删除后可能不足一屏，横向列表滚不动就再也触发不了翻页，这里主动补一页
            if refillAfterRefresh {
                refillAfterRefresh = false
                if items.count < store.pageSize {
                    loadNextPage()
                }
            }
        }
    }

    private func handleStoreChange(_ change: PasteDataStore.Change) {
        if isVisible {
            if change == .userDeleted {
                refillAfterRefresh = true
            }
            refreshLoaded()
        } else {
            // 面板隐藏时直接回到默认列表第一页，下次打开就是最新内容
            reload()
        }
    }

    private func apply(_ list: [PasteboardModel], animated: Bool, scrollToBeginning: Bool = false, dataChanged: Bool = false) {
        // diffable 数据源遇到重复标识会直接崩溃。正常情况下 hashKey 唯一索引保证不重复，
        // 这里兜底：唯一索引没建成的库、或翻页与刷新交错时，同一条只保留第一次出现的位置
        var seen = Set<Int>()
        let newItems = list.filter { seen.insert($0.hashValue).inserted }
        let old = Dictionary(items.map { ($0.hashValue, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedHash = item(at: selectedIndexPath)?.hashValue
        var update = ListUpdate(animated: animated, scrollToBeginning: scrollToBeginning, dataChanged: dataChanged)
        for model in newItems {
            guard let previous = old[model.hashValue] else { continue }
            if previous.date != model.date || previous.ocrText != model.ocrText || previous.appPath != model.appPath {
                update.reloaded.append(model.hashValue)
            } else if previous.pinnedDate != model.pinnedDate {
                update.pinChanged.append(model)
            }
        }
        items = newItems
        if scrollToBeginning {
            selectedIndexPath = IndexPath(item: 0, section: 0)
        } else if let selectedHash, let index = newItems.firstIndex(where: { $0.hashValue == selectedHash }) {
            // 选中跟随原来那一条
            selectedIndexPath = IndexPath(item: index, section: 0)
        } else {
            // 原来选中的被删了：停在原位置，即选中它后面那条
            selectedIndexPath = IndexPath(item: min(selectedIndexPath.item, max(newItems.count - 1, 0)), section: 0)
            update.scrollToSelection = !newItems.isEmpty
        }
        listUpdate.send(update)
    }
}

// MARK: - 搜索与筛选

extension PasteMainViewModel {
    func performSearch(keyword: String) {
        if keyword.isEmpty && !filterIsActive {
            resetToDefaultList()
        } else {
            reload(keyword: keyword, state: filterState)
            Log("search start: \(keyword), filter: \(filterState)")
        }
    }

    func resetToDefaultList() {
        reload()
    }

    func updateFilter(_ state: FilterState) {
        filterState = state
    }

    func removeLastFilterTag(from filterView: PasteFilterView) {
        if filterState.selectedDateRange != nil {
            filterView.removeFilter(.date)
        } else if filterState.selectedType != nil {
            filterView.removeFilter(.type)
        } else if filterState.selectedApp != nil {
            filterView.removeFilter(.app)
        }
    }

    func typeCounts() async -> TypeCounts {
        await store.typeCounts()
    }

    func topApps() async -> [(name: String, path: String)] {
        await store.topApps()
    }

    func allApps() async -> [(name: String, path: String)] {
        await store.allApps()
    }
}

// MARK: - 条目操作与选中

extension PasteMainViewModel {
    func item(at indexPath: IndexPath) -> PasteboardModel? {
        guard indexPath.item < items.count else { return nil }
        return items[indexPath.item]
    }

    func deleteItem(at indexPath: IndexPath) {
        guard let item = item(at: indexPath) else { return }
        store.deleteItems(item)
    }

    /// 切换某条目的置顶状态(置顶↔取消置顶)
    func togglePin(for model: PasteboardModel) {
        store.setPinned(!model.isPinned, for: model)
    }

    func resetSelection(to indexPath: IndexPath = IndexPath(item: 0, section: 0)) {
        selectedIndexPath = indexPath
    }
}

// MARK: - 粘贴与复制

extension PasteMainViewModel {
    func pasteItem(at indexPath: IndexPath, isOriginal: Bool = true) {
        guard let model = item(at: indexPath) else { return }
        pasteModel(model, isOriginal: isOriginal)
    }

    func pasteModel(_ model: PasteboardModel, isOriginal: Bool) {
        Log("isOriginal: \(isOriginal) data: \(model.dataString)")
        guard PasteUserDefaults.pasteDirect else {
            Task {
                let ready = await resolvePasteModel(model)
                PasteBoard.main.pasteData(ready, isOriginal)
            }
            return
        }
        // 先加载好原图(图片已外置到文件)，再播放关闭动画，待窗口隐藏后写剪贴板、激活前台并粘贴。
        // 这样既不会因提前 activateFrontApp 打断动画，也不会在窗口可见时触发列表跳动刷新。
        Task {
            let ready = await resolvePasteModel(model)
            AppContext.coordinator.dismissWindow {
                PasteBoard.main.pasteData(ready, isOriginal)
                AppContext.coordinator.activateFrontApp()
                KeyboardShortcuts.postCmdVEvent()
            }
        }
    }

    func copyModel(_ model: PasteboardModel) {
        // 同 pasteModel：先加载原图，再等关闭动画结束、窗口隐藏后写剪贴板，避免列表在可见时跳动。
        Task {
            let ready = await resolvePasteModel(model)
            AppContext.coordinator.dismissWindow {
                PasteBoard.main.pasteData(ready)
                AppContext.coordinator.activateFrontApp()
            }
        }
    }

    /// 把要粘贴/复制的 model 补全为可写入剪贴板的形态:
    /// 图片的 data 在列表中是缩略图，需按需换回原图;非图片原样返回。
    private func resolvePasteModel(_ model: PasteboardModel) async -> PasteboardModel {
        guard model.type == .image else { return model }
        let original = await store.loadOriginalImageData(for: model)
        return original == model.data ? model : model.replacingData(original)
    }

    /// 复制图片中的文字到剪贴板(并进入历史)
    func copyOCRText(from model: PasteboardModel) {
        Task {
            guard let text = await resolveOCRText(for: model) else { return }
            let textModel = PasteboardModel.makeText(text, from: model)
            copyModel(textModel)
        }
    }

    /// 把图片中的文字以纯文本粘贴到前台 App
    func pasteOCRText(from model: PasteboardModel) {
        Task {
            guard let text = await resolveOCRText(for: model) else { return }
            let textModel = PasteboardModel.makeText(text, from: model)
            pasteModel(textModel, isOriginal: false)
        }
    }

    /// 取得图片的 OCR 文字:已识别过直接返回,未识别则当场识别。
    /// 图中确无文字时返回 nil。
    private func resolveOCRText(for model: PasteboardModel) async -> String? {
        if let text = model.ocrText, !text.isEmpty { return text }
        return await PasteDataStore.main.extractOCRText(from: model)
    }
}

// MARK: - 生命周期

extension PasteMainViewModel {
    func handleViewDidAppear() {
        isVisible = true
    }

    func handleViewDidDisappear(needsReset: Bool) {
        isVisible = false
        filterState = .empty
        store.clearExpiredData()
        if needsReset {
            resetToDefaultList()
        }
    }
}
