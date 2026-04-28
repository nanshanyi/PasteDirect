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

    @Published private(set) var items: [PasteboardModel] = []
    @Published var selectedIndexPath = IndexPath(item: 0, section: 0)
    @Published private(set) var canLoadMore = true

    /// 数据变化事件（区分 reload 和 delete）
    enum DataChange {
        case reload(scrollToBeginning: Bool)
        case delete(IndexPath)
    }

    let dataChange = PassthroughSubject<DataChange, Never>()

    // MARK: - 筛选状态

    var filterState = FilterState.empty
    var filterIsActive: Bool { filterState.isActive }

    // MARK: - Private

    private let store = PasteDataStore.main
    private var cancellables = Set<AnyCancellable>()
    private var suppressReload = false
    private var needsScrollToBeginning = false

    init() {
        initObserve()
    }
    
    private func initObserve() {
        store.dataList
            .receive(on: DispatchQueue.main)
            .filter { [weak self] _ in
                guard let self else { return false }
                if self.suppressReload {
                    self.suppressReload = false
                    return false
                }
                return true
            }
            .sink { [weak self] items in
                guard let self else { return }
                self.items = items
                let scroll = self.needsScrollToBeginning
                self.needsScrollToBeginning = false
                self.dataChange.send(.reload(scrollToBeginning: scroll))
            }
            .store(in: &cancellables)
        
        store.$loadState
            .sink { [weak self] state in
                self?.canLoadMore = (state == .idle)
            }
            .store(in: &cancellables)
    }

    // MARK: - 搜索 & 筛选

    func performSearch(keyword: String) {
        if keyword.isEmpty && !filterIsActive {
            resetToDefaultList()
        } else {
            resetSelection()
            needsScrollToBeginning = true
            store.searchData(keyword, filter: filterState)
            Log("search start: \(keyword), filter: \(filterState)")
        }
    }

    func resetToDefaultList() {
        resetSelection()
        needsScrollToBeginning = true
        store.resetDefaultList()
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

    func topApps() async -> [(name: String, path: String)] {
        await store.topApps()
    }

    func allApps() async -> [(name: String, path: String)] {
        await store.allApps()
    }

    // MARK: - 数据操作

    func deleteItem(at indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        let item = items[indexPath.item]
        suppressReload = true
        store.deleteItems(item)
        items.remove(at: indexPath.item)
        dataChange.send(.delete(indexPath))
        resetSelection(to: indexPath)
    }

    func loadNextPage() {
        store.loadNextPage()
    }

    func item(at indexPath: IndexPath) -> PasteboardModel? {
        guard indexPath.item < items.count else { return nil }
        return items[indexPath.item]
    }

    // MARK: - 选中

    func selectItem(at indexPath: IndexPath) {
        selectedIndexPath = indexPath
    }

    func resetSelection(to indexPath: IndexPath = IndexPath(item: 0, section: 0)) {
        selectedIndexPath = indexPath
    }

    // MARK: - 粘贴

    func pasteItem(at indexPath: IndexPath, isOriginal: Bool = true) {
        guard let model = item(at: indexPath) else { return }
        pasteModel(model, isOriginal: isOriginal)
    }

    func pasteModel(_ model: PasteboardModel, isOriginal: Bool) {
        Log("isOriginal: \(isOriginal) data: \(model.dataString)")
        PasteBoard.main.pasteData(model, isOriginal)
        guard PasteUserDefaults.pasteDirect else { return }
        AppContext.coordinator.activateFrontApp()
        AppContext.coordinator.dismissWindow()
        KeyboardShortcuts.postCmdVEvent()
    }

    func copyModel(_ model: PasteboardModel) {
        AppContext.coordinator.dismissWindow()
        PasteBoard.main.pasteData(model)
        AppContext.coordinator.activateFrontApp()
    }

    // MARK: - 生命周期

    func handleViewDidAppear() {
        if store.needRefresh {
            store.needRefresh = false
            resetToDefaultList()
        }
    }

    func handleViewDidDisappear(needsReset: Bool) {
        filterState = .empty
        store.clearExpiredData()
        if needsReset {
            resetToDefaultList()
        }
    }
}
