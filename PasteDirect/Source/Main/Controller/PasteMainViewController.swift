//
//  PasteMainViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import AppKit
import Carbon
import Cocoa
import Combine
import SnapKit

final class PasteMainViewController: NSViewController {
    private var selectIndexPath = IndexPath(item: 0, section: 0)
    private var dataList = PasteDataStore.main.dataList
    private var cancellables = Set<AnyCancellable>()
    private var deleteItem = false
    private var currentFilterState = FilterState.empty

    // MARK: - lazy property

    private lazy var collectionView = NSCollectionView().then {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = Layout.itemSize
        flowLayout.minimumInteritemSpacing = Layout.lineSpacing
        flowLayout.minimumLineSpacing = Layout.lineSpacing
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = NSEdgeInsets(top: 0, left: Layout.lineSpacing, bottom: 0, right: Layout.lineSpacing)
        $0.wantsLayer = true
        $0.delegate = self
        $0.dataSource = self
        $0.allowsEmptySelection = false
        $0.backgroundColors = [.clear]
        $0.collectionViewLayout = flowLayout
        $0.isSelectable = true
        $0.register(PasteCollectionViewItem.self)
        $0.registerForDraggedTypes(PasteboardType.supportTypes)
        $0.setDraggingSourceOperationMask(.every, forLocal: true)
        $0.setDraggingSourceOperationMask(.every, forLocal: false)
    }

    private lazy var scrollView = PasteScrollView().then {
        $0.documentView = collectionView
        $0.scrollerStyle = .overlay
        $0.autohidesScrollers = true
        $0.verticalScrollElasticity = .none
        $0.horizontalScrollElasticity = .automatic
        $0.delegate = self
    }

    private lazy var effectView: NSView = {
        if #available(macOS 26.0, *) {
           let glassView = NSGlassEffectView()
            glassView.frame = view.frame
            glassView.cornerRadius = 34
            glassView.contentView = contentView
            return glassView
        } else {
           let effectView = NSVisualEffectView()
            effectView.wantsLayer = true
            effectView.frame = view.frame
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.layer?.cornerRadius = 34
            return effectView
        }
    }()

    private lazy var searchBar = PasteSearchField().then {
        $0.cell?.controlSize = .large
        $0.focusRingType = .none
        $0.refusesFirstResponder = true
        $0.placeholderString = String(localized: "Search")
        $0.delegate = self
    }

    private lazy var contentView = NSView().then {
        $0.wantsLayer = true
        $0.layer?.backgroundColor = .clear
        $0.layer?.cornerRadius = 34
        $0.layer?.masksToBounds = true
    }
    
    private lazy var settingButton = NSButton().then {
        $0.isBordered = false
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let icon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        $0.image = icon?.withSymbolConfiguration(config)
        $0.contentTintColor = .labelColor
    }

    private lazy var filterView = PasteFilterView(frame: NSRect(x: 0, y: 0, width: PasteFilterView.contentWidth, height: 300))

    private lazy var filterPopover = NSPopover().then {
        $0.behavior = .transient
        $0.animates = true
        $0.contentSize = NSSize(width: PasteFilterView.contentWidth, height: 300)
        let vc = NSViewController()
        vc.view = filterView
        $0.contentViewController = vc
    }
}

// MARK: - 生命周期

extension PasteMainViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        initCombine()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: keyDownEvent(_:))
    }

    override func viewDidAppear() {
        view.window?.makeFirstResponder(collectionView)
        view.frame = NSRect(x: view.frame.origin.x, y: -Layout.viewHeight, width: view.frame.width, height: Layout.viewHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.view.animator().setFrameOrigin(.zero)
        }
        if PasteDataStore.main.needRefresh {
            PasteDataStore.main.needRefresh.toggle()
            if dataList.value.count < PasteDataStore.main.pageSize {
                resetToDefaultList()
            } else {
                resetSelectIndex()
                collectionView.reloadData()
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        searchBar.objectValue = nil
        filterView.resetFilter()
        currentFilterState = .empty
        updateFilterButtonAppearance()
        searchBar.updateTags([])
        PasteDataStore.main.clearExpiredData()
    }
}

// MARK: - UI & Rx

extension PasteMainViewController {
    private func initSubviews() {
        view.wantsLayer = true
        view.addSubview(effectView)
        if effectView is NSVisualEffectView {
            effectView.addSubview(contentView)
            contentView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        contentView.addSubview(scrollView)
        contentView.addSubview(searchBar)
        contentView.addSubview(settingButton)
        effectView.snp.makeConstraints { make in
            make.leading.equalTo(8)
            make.trailing.equalTo(-8)
            make.top.equalToSuperview()
            make.bottom.equalTo(-8)
        }

        scrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().offset(-20)
            make.top.equalTo(searchBar.snp.bottom).offset(20)
        }

        searchBar.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(20)
            make.height.equalTo(Layout.searchBarHeight)
            make.width.equalTo(Layout.searchBarWidth)
        }

        settingButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalTo(searchBar)
            make.width.height.equalTo(44)
        }
    }

    private func initCombine() {
        // 搜索框文本变化监听
        searchBar.$text
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                self.performSearch()
            }
            .store(in: &cancellables)

        // 数据列表变化监听
        dataList
            .receive(on: DispatchQueue.main)
            .filter { [weak self] _ in self?.deleteItem == false }
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.deleteItem = false
                self.collectionView.reloadData()
            }
            .store(in: &cancellables)

        // loadState 监听 → 控制 scrollView.canLoadMore
        PasteDataStore.main.$loadState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.scrollView.canLoadMore = (state == .idle)
            }
            .store(in: &cancellables)

        // 设置按钮点击监听
        settingButton.tapPublisher
            .sink { [weak self] in
                self?.settingAction()
            }
            .store(in: &cancellables)

        // 筛选按钮点击
        searchBar.filterButton.tapPublisher
            .sink { [weak self] in
                self?.showFilterPopover()
            }
            .store(in: &cancellables)

        // 筛选状态变化监听
        filterView.$filterState
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self = self else { return }
                self.currentFilterState = state
                self.updateFilterButtonAppearance()
                self.searchBar.updateTags(state.activeTags)
                self.performSearch()
            }
            .store(in: &cancellables)
    }
}

// MARK: - 私有方法

extension PasteMainViewController {
    private func searchWord(_ keyword: String) {
        performSearch()
    }

    /// 按倒序移除最后一个筛选标签：日期 > 类型 > 应用
    private func removeLastFilterTag() {
        if filterView.filterState.selectedDateRange != nil {
            filterView.removeFilter(.date)
        } else if filterView.filterState.selectedType != nil {
            filterView.removeFilter(.type)
        } else if filterView.filterState.selectedApp != nil {
            filterView.removeFilter(.app)
        }
    }

    private func performSearch() {
        let keyword = searchBar.text
        let hasFilter = currentFilterState.isActive
        if keyword.isEmpty && !hasFilter {
            resetToDefaultList()
        } else {
            resetSelectIndex()
            PasteDataStore.main.searchData(keyword, filter: currentFilterState)
            Log("search start: \(keyword), filter: \(currentFilterState)")
            collectionView.scroll(.zero)
        }
    }

    private func showFilterPopover() {
        if filterPopover.isShown {
            filterPopover.close()
            return
        }
        let topApps = PasteDataStore.main.topApps()
        let allApps = PasteDataStore.main.allApps()
        filterView.configure(apps: topApps, allApps: allApps)
        let btn = searchBar.filterButton
        filterPopover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .maxY)
    }

    private func updateFilterButtonAppearance() {
        searchBar.filterButton.contentTintColor = currentFilterState.isActive ? .controlAccentColor : .secondaryLabelColor
    }

    private func resetToDefaultList() {
        resetSelectIndex()
        PasteDataStore.main.resetDefaultList()
    }

    private func keyDownEvent(_ event: NSEvent) -> NSEvent? {
        if KeyHelper.numberCharacters.contains(where: { $0 == event.keyCode }) {
            if !searchBar.isFirstResponder {
                view.window?.makeFirstResponder(searchBar)
            }
        } else if event.keyCode == kVK_Escape {
            escapeKeyDown()
        } else if event.keyCode == kVK_Delete {
            deleteKeyDown()
        } else if event.keyCode == kVK_Return {
            returnKeyDown()
        }
        return event
    }
    
    private func escapeKeyDown() {
        if filterPopover.isShown {
            filterPopover.close()
        } else if searchBar.isFirstResponder {
            let needRefresh = !searchBar.text.isEmpty || currentFilterState.isActive
            searchBar.objectValue = nil
            filterView.resetFilter()
            currentFilterState = .empty
            updateFilterButtonAppearance()
            searchBar.updateTags([])
            view.window?.makeFirstResponder(collectionView)
            if needRefresh {
                resetToDefaultList()
            }
        } else if currentFilterState.isActive {
            filterView.resetFilter()
            currentFilterState = .empty
            updateFilterButtonAppearance()
            searchBar.updateTags([])
            resetToDefaultList()
        } else {
            let app = NSApplication.shared.delegate as? PasteAppDelegate
            app?.dismissWindow()
        }
    }
    
    private func deleteKeyDown() {
        guard !searchBar.isFirstResponder else { return }
        if selectIndexPath.item < dataList.value.count {
            let item = dataList.value[selectIndexPath.item]
            deleteItem(item, indexPath: selectIndexPath)
        }
    }
    
    private func returnKeyDown() {
        guard !searchBar.isFirstResponder else { return }
        guard let item = collectionView.item(at: selectIndexPath) as? PasteCollectionViewItem else { return }
        item.pasteItem()
    }

    private func resetSelectIndex(_ indexPath: IndexPath = IndexPath(item: 0, section: 0)) {
        collectionView.item(at: selectIndexPath)?.isSelected = false
        selectIndexPath = indexPath
        if !dataList.value.isEmpty {
            collectionView.selectionIndexPaths = [selectIndexPath]
            scrollTo(indexPath: selectIndexPath)
        }
    }
    
    private func settingAction() {
        let app = NSApplication.shared.delegate as? PasteAppDelegate
        app?.settingsAction()
    }
    
    private func scrollTo(indexPath: IndexPath) {
       if let item = collectionView.layoutAttributesForItem(at: indexPath) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                collectionView.animator().scrollToVisible(NSRect(x: item.frame.origin.x - Layout.lineSpacing, y: 0, width: item.frame.width + Layout.lineSpacing * 2, height: item.frame.height))
            }
        }
    }
}

// MARK: - NSCollectionViewDelegate

extension PasteMainViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        if let indexPath = indexPaths.first {
            resetSelectIndex(indexPath)
        }
        Log("选中\(indexPaths.description)")
        return [selectIndexPath]
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        Log("Drag \(indexPaths.description)")
        return true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        return dataList.value[indexPath.item].writeItem
    }
}

// MARK: - NSCollectionViewDataSource

extension PasteMainViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataList.value.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PasteCollectionViewItem.identifier, for: indexPath)
        guard let cItem = item as? PasteCollectionViewItem else { return item }
        cItem.delegate = self
        cItem.updateItem(model: dataList.value[indexPath.item])
        if selectIndexPath == indexPath {
            cItem.isSelected = true
            collectionView.selectionIndexPaths = [indexPath]
        } else {
            cItem.isSelected = false
        }
        return cItem
    }
}

// MARK: - PasteScrollViewDelegate

extension PasteMainViewController: PasteScrollViewDelegate {
    func loadMoreData() {
        PasteDataStore.main.loadNextPage()
    }
}

// MARK: - PasteCollectionViewItemDelegate

extension PasteMainViewController: PasteCollectionViewItemDelegate {
    func deleteItem(_ item: PasteboardModel, indexPath: IndexPath) {
        defer { deleteItem = false }
        deleteItem = true
        PasteDataStore.main.deleteItems(item)
        collectionView.animator().deleteItems(at: [indexPath])
        resetSelectIndex(indexPath)
    }
}


extension PasteMainViewController: NSSearchFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        view.window?.makeFirstResponder(collectionView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            if textView.string.isEmpty && currentFilterState.isActive {
                removeLastFilterTag()
                return true
            }
        }
        return false
    }
}
