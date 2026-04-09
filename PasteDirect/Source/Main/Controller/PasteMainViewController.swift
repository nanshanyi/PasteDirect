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
    private let viewModel = PasteMainViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var previewPopover: PastePreviewPopover?
    private var contentView: NSView!

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

    private lazy var searchBar = PasteSearchField().then {
        $0.cell?.controlSize = .large
        $0.focusRingType = .none
        $0.refusesFirstResponder = true
        $0.placeholderString = String(localized: "Search")
        $0.delegate = self
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
    override func loadView() {
        let contentView = NSView()
        contentView.wantsLayer = true
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = 34
            glassView.contentView = contentView
            view = glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.wantsLayer = true
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.layer?.cornerRadius = 34
            effectView.layer?.masksToBounds = true
            effectView.addSubview(contentView)
            contentView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            view = effectView
        }
        self.contentView = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        bindViewModel()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: keyDownEvent(_:))
    }

    override func viewDidAppear() {
        view.window?.makeFirstResponder(collectionView)
        viewModel.handleViewDidAppear()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        closePreviewPopover()
        searchBar.objectValue = nil
        filterView.resetFilter()
        viewModel.handleViewDidDisappear()
        updateFilterButtonAppearance()
        searchBar.updateTags([])
    }
}

// MARK: - UI & 绑定

extension PasteMainViewController {
    private func initSubviews() {
        contentView.addSubview(scrollView)
        contentView.addSubview(searchBar)
        contentView.addSubview(settingButton)

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

    private func bindViewModel() {
        // 搜索框文本
        searchBar.$text
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.viewModel.performSearch(keyword: self.searchBar.text)
            }
            .store(in: &cancellables)

        // 数据变化
        viewModel.dataChange
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .reload(let scrollToBeginning):
                    self.collectionView.reloadData()
                    if scrollToBeginning {
                        self.collectionView.scroll(.zero)
                    }
                case .delete(let indexPath):
                    self.collectionView.animator().deleteItems(at: [indexPath])
                    self.resetSelectIndex(indexPath)
                }
            }
            .store(in: &cancellables)

        // canLoadMore
        viewModel.$canLoadMore
            .sink { [weak self] canLoad in
                self?.scrollView.canLoadMore = canLoad
            }
            .store(in: &cancellables)

        // 设置按钮
        settingButton.tapPublisher
            .sink { [weak self] in
                self?.settingAction()
            }
            .store(in: &cancellables)

        // 筛选按钮
        searchBar.filterButton.tapPublisher
            .sink { [weak self] in
                self?.showFilterPopover()
            }
            .store(in: &cancellables)

        // 筛选状态变化
        filterView.$filterState
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                self.viewModel.updateFilter(state)
                self.updateFilterButtonAppearance()
                self.searchBar.updateTags(state.activeTags)
                self.viewModel.performSearch(keyword: self.searchBar.text)
            }
            .store(in: &cancellables)
    }
}

// MARK: - 私有方法

extension PasteMainViewController {
    private func showFilterPopover() {
        if filterPopover.isShown {
            filterPopover.close()
            return
        }
        filterView.configure(apps: viewModel.topApps(), allApps: viewModel.allApps())
        let btn = searchBar.filterButton
        filterPopover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .maxY)
    }

    private func updateFilterButtonAppearance() {
        searchBar.filterButton.contentTintColor = viewModel.filterIsActive ? .controlAccentColor : .secondaryLabelColor
    }

    private func settingAction() {
        AppContext.coordinator.showSettings()
    }

    private func resetSelectIndex(_ indexPath: IndexPath = IndexPath(item: 0, section: 0)) {
        let old = viewModel.selectedIndexPath
        collectionView.item(at: old)?.isSelected = false
        viewModel.resetSelection(to: indexPath)
        if !viewModel.items.isEmpty {
            collectionView.selectionIndexPaths = [indexPath]
            scrollTo(indexPath: indexPath)
        }
    }

    private func scrollTo(indexPath: IndexPath) {
        if let item = collectionView.layoutAttributesForItem(at: indexPath) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                collectionView.animator().scrollToVisible(NSRect(x: item.frame.origin.x - Layout.lineSpacing, y: 0, width: item.frame.width + Layout.lineSpacing * 2, height: item.frame.height))
            }
        }
    }

    private func showPreviewPopover(for model: PasteboardModel, relativeTo view: NSView) {
        closePreviewPopover()
        let popover = PastePreviewPopover(model: model)
        previewPopover = popover
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    private func closePreviewPopover() {
        previewPopover?.close()
        previewPopover = nil
    }
}

// MARK: - 键盘事件

extension PasteMainViewController {
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
        } else if event.keyCode == 49 { // kVK_Space
            spaceKeyDown()
        }
        return event
    }

    private func escapeKeyDown() {
        if previewPopover?.isShown == true {
            closePreviewPopover()
        } else if filterPopover.isShown {
            filterPopover.close()
        } else if searchBar.isFirstResponder {
            let needRefresh = !searchBar.text.isEmpty || viewModel.filterIsActive
            searchBar.objectValue = nil
            filterView.resetFilter()
            viewModel.updateFilter(.empty)
            updateFilterButtonAppearance()
            searchBar.updateTags([])
            view.window?.makeFirstResponder(collectionView)
            if needRefresh {
                viewModel.resetToDefaultList()
            }
        } else if viewModel.filterIsActive {
            filterView.resetFilter()
            viewModel.updateFilter(.empty)
            updateFilterButtonAppearance()
            searchBar.updateTags([])
            viewModel.resetToDefaultList()
        } else {
            AppContext.coordinator.dismissWindow()
        }
    }

    private func deleteKeyDown() {
        guard !searchBar.isFirstResponder else { return }
        viewModel.deleteItem(at: viewModel.selectedIndexPath)
    }

    private func returnKeyDown() {
        guard !searchBar.isFirstResponder else { return }
        viewModel.pasteItem(at: viewModel.selectedIndexPath)
    }

    private func spaceKeyDown() {
        guard !searchBar.isFirstResponder else { return }
        if previewPopover?.isShown == true {
            closePreviewPopover()
        } else {
            guard let model = viewModel.item(at: viewModel.selectedIndexPath),
                  let itemView = collectionView.item(at: viewModel.selectedIndexPath)?.view else { return }
            showPreviewPopover(for: model, relativeTo: itemView)
        }
    }
}

// MARK: - NSCollectionViewDelegate

extension PasteMainViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        if let indexPath = indexPaths.first {
            resetSelectIndex(indexPath)
            if previewPopover?.isShown == true, let model = viewModel.item(at: indexPath) {
                if let itemView = collectionView.item(at: indexPath)?.view {
                    showPreviewPopover(for: model, relativeTo: itemView)
                }
            }
        }
        Log("选中\(indexPaths.description)")
        return [viewModel.selectedIndexPath]
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        Log("Drag \(indexPaths.description)")
        return true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        return viewModel.item(at: indexPath)?.writeItem
    }
}

// MARK: - NSCollectionViewDataSource

extension PasteMainViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PasteCollectionViewItem.identifier, for: indexPath)
        guard let cItem = item as? PasteCollectionViewItem else { return item }
        cItem.delegate = self
        if let model = viewModel.item(at: indexPath) {
            cItem.updateItem(model: model)
        }
        if viewModel.selectedIndexPath == indexPath {
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
        viewModel.loadNextPage()
    }
}

// MARK: - PasteCollectionViewItemDelegate

extension PasteMainViewController: PasteCollectionViewItemDelegate {
    func deleteItem(_ item: PasteboardModel, indexPath: IndexPath) {
        viewModel.deleteItem(at: indexPath)
    }

    func previewItem(_ item: PasteboardModel, relativeTo view: NSView) {
        if previewPopover?.isShown == true {
            closePreviewPopover()
        } else {
            showPreviewPopover(for: item, relativeTo: view)
        }
    }

    func pasteItem(_ item: PasteboardModel, isOriginal: Bool) {
        viewModel.pasteModel(item, isOriginal: isOriginal)
    }

    func copyItem(_ item: PasteboardModel) {
        viewModel.copyModel(item)
    }
}

// MARK: - NSSearchFieldDelegate

extension PasteMainViewController: NSSearchFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        view.window?.makeFirstResponder(collectionView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            if textView.string.isEmpty && viewModel.filterIsActive {
                viewModel.removeLastFilterTag(from: filterView)
                return true
            }
        }
        return false
    }
}
