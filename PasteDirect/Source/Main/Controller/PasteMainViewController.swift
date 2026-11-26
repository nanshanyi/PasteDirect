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
    private var keyEventMonitor: Any?
    private var contentView: NSView!
    private var isBouncingBack = false

    // MARK: - lazy property

    private lazy var collectionView = PasteCollectionView().then {
        let flowLayout = PasteFlowLayout()
        // 一开始就用当前面板高度对应的尺寸:若先用固定的 260,首批 cell 会按错误高度配置(图钉、头部偏大)
        flowLayout.itemSize = Layout.dynamicItemSize(for: Layout.viewHeight)
        flowLayout.minimumInteritemSpacing = Layout.lineSpacing - Layout.itemShadowMargin * 2
        flowLayout.minimumLineSpacing = Layout.lineSpacing - Layout.itemShadowMargin * 2
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = NSEdgeInsets(top: 0, left: Layout.lineSpacing - Layout.itemShadowMargin, bottom: 0,
                                               right: Layout.lineSpacing - Layout.itemShadowMargin)
        $0.wantsLayer = true
        $0.delegate = self
        $0.keyDelegate = self
        $0.allowsEmptySelection = false
        $0.backgroundColors = [.clear]
        flowLayout.pinnedCountProvider = { [weak self] in
            self?.viewModel.items.prefix { $0.isPinned }.count ?? 0
        }
        $0.collectionViewLayout = flowLayout
        $0.isSelectable = true
        $0.register(PasteCollectionViewItem.self)
        $0.registerForDraggedTypes(PasteboardType.supportTypes)
        $0.setDraggingSourceOperationMask(.every, forLocal: true)
        $0.setDraggingSourceOperationMask(.every, forLocal: false)
    }

    /// 以条目 hash 为标识，列表变化时自动计算插入/删除/移动动画
    private lazy var dataSource = NSCollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { [weak self] collectionView, indexPath, _ in
        self?.makeItem(collectionView, at: indexPath)
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
        $0.placeholderString = String(localized: "Search")
        $0.delegate = self
    }

    private lazy var settingButton = ToolbarIconButton(symbol: "gearshape", toolTip: String(localized: "Settings"))

    /// 顶栏左侧的类型分段按钮:全部 + PasteModelType.filterable 中的各类型
    private static let segmentTypes: [PasteModelType?] = [nil] + PasteModelType.filterable

    private lazy var typeSegment = PillSegmentedControl(
        titles: Self.segmentTypes.map { $0?.string ?? String(localized: "All") }
    ).then {
        $0.onChange = { [weak self] _ in self?.typeSegmentChanged() }
    }

    /// 顶部居中的拖拽把手,提示面板高度可调
    private lazy var grabber = PillLayerView().then {
        $0.fill = { AppColor.grabber(active: false) }
        $0.radius = 2.5
    }

    /// 当前是否在显示 ⌘ 快速粘贴编号
    private var isShowingShortcuts = false

    private lazy var filterView = PasteFilterView(frame: NSRect(x: 0, y: 0, width: PasteFilterView.contentWidth, height: Layout.filterPopoverHeight))

    private lazy var filterPopover = NSPopover().then {
        $0.behavior = .transient
        $0.animates = true
        $0.contentSize = NSSize(width: PasteFilterView.contentWidth, height: Layout.filterPopoverHeight)
        let vc = NSViewController()
        vc.view = filterView
        $0.contentViewController = vc
    }

    private lazy var emptyStateView = PasteEmptyStateView().then {
        $0.isHidden = true
    }

    private lazy var resizeHandle = PanelResizeHandle()

    private lazy var pinRail = PastePinRailView().then {
        $0.isHidden = true
    }

    /// 列表左边缘：有置顶折叠条时让出它的位置
    private var scrollLeading: Constraint?
    /// 展开时竖条和置顶卡片共用的那块底色：还是列表原来那个置顶分组装饰视图，
    /// 只是 frame 由控制器从竖条左边缘算起（布局算的那块够不到竖条，会被列表左缘裁掉）
    private let pinnedGroupBackground = PinnedGroupBackgroundView(frame: .zero)
    private var pinPeekPopover: NSPopover?
    private var isRailHovered = false
    private var isPeekHovered = false
    /// 按住 ⌥ 时弹出置顶清单显示 ⌥1–9
    private var isOptionHeld = false
    /// 悬停一小会儿才弹出清单，鼠标只是划过时不打扰
    private var peekShowTask: Task<Void, Never>?
}

// MARK: - 生命周期

extension PasteMainViewController {
    override func loadView() {
        let contentView = NSView()
        contentView.wantsLayer = true
        let panelView: NSView
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = Layout.cornerRadius
            glassView.contentView = contentView
            panelView = glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.wantsLayer = true
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.layer?.cornerRadius = Layout.cornerRadius
            effectView.layer?.masksToBounds = true
            effectView.addSubview(contentView)
            contentView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            panelView = effectView
        }
        // 窗口四周比面板大出 panelShadowMargin 的透明边距，给玻璃的阴影留出淡出空间
        let container = NSView()
        container.addSubview(panelView)
        panelView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.panelShadowMargin)
        }
        view = container
        self.contentView = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        _ = dataSource
        bindViewModel()
        viewModel.start()
        setupKeyEventMonitor()
        updateEmptyState()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if isBouncingBack, let window = view.window {
            updateItemSize(for: Self.panelHeight(of: window))
        }
        // 面板高度变化会改卡片尺寸，分组底色跟着重算
        updatePinnedGroupBackground()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(collectionView)
        viewModel.handleViewDidAppear()
        updateItemSize(for: Layout.viewHeight)
        refreshTypeCounts()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        closePreviewPopover()
        isOptionHeld = false
        closePinPeek()
        let hadSearchOrFilter = !searchBar.text.isEmpty || viewModel.filterIsActive
        searchBar.stringValue = ""
        filterView.resetFilter()
        viewModel.handleViewDidDisappear(needsReset: hadSearchOrFilter)
        updateFilterButtonAppearance()
        searchBar.updateTags([])
        typeSegment.selectedIndex = 0
        setShortcutHintsVisible(false)
        PasteCollectionViewItem.clearHover()
    }
}

// MARK: - UI & 绑定

extension PasteMainViewController {
    private func initSubviews() {
        // 置顶分组底色要铺在列表下面：先加它，再加滚动视图和竖条
        pinnedGroupBackground.isHidden = true
        contentView.addSubview(pinnedGroupBackground)
        contentView.addSubview(scrollView)
        contentView.addSubview(pinRail)
        contentView.addSubview(emptyStateView)
        contentView.addSubview(searchBar)
        contentView.addSubview(settingButton)
        contentView.addSubview(typeSegment)
        contentView.addSubview(grabber)
        contentView.addSubview(resizeHandle)

        resizeHandle.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(Layout.resizeHandleHeight)
        }

        scrollView.snp.makeConstraints { make in
            scrollLeading = make.leading.equalToSuperview().constraint
            make.trailing.equalToSuperview()
            // 上下各收 itemShadowMargin,抵消卡片内缩带来的额外间距,回到原视觉间距
            make.bottom.equalToSuperview().offset(-Layout.scrollViewBottom + Layout.itemShadowMargin)
            make.top.equalTo(searchBar.snp.bottom).offset(Layout.scrollViewTop - Layout.itemShadowMargin)
        }

        emptyStateView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView)
        }

        // 和卡片上下对齐：cell 上下各有 itemShadowMargin 的留白
        pinRail.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.padding)
            make.width.equalTo(PastePinRailView.width)
            make.top.equalTo(scrollView).offset(Layout.itemShadowMargin)
            make.bottom.equalTo(scrollView).offset(-Layout.itemShadowMargin)
        }
        setupPinRail()

        searchBar.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(Layout.searchBarTop)
            make.height.equalTo(Layout.searchBarHeight)
            make.width.equalTo(Layout.searchBarWidth)
        }

        grabber.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(resizeHandle)
            make.width.equalTo(36)
            make.height.equalTo(5)
        }

        typeSegment.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.padding)
            make.centerY.equalTo(searchBar)
            make.trailing.lessThanOrEqualTo(searchBar.snp.leading).offset(-12)
        }

        settingButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Layout.settingButtonTrailing)
            make.centerY.equalTo(searchBar)
            make.width.height.equalTo(Layout.settingButtonSize)
        }

        setupResizeHandle()
        // 悬停/拖动时把手变亮变宽,提示可以拖
        resizeHandle.onActiveChange = { [weak self] active in
            guard let self else { return }
            self.grabber.fill = { AppColor.grabber(active: active) }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                self.grabber.snp.updateConstraints { make in make.width.equalTo(active ? 48 : 36) }
                self.contentView.layoutSubtreeIfNeeded()
            }
        }
        updateItemSize(for: Layout.viewHeight)
    }

    private func bindViewModel() {
        // 搜索框文本
        searchBar.$text
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.viewModel.performSearch(keyword: self.searchBar.text)
            }
            .store(in: &cancellables)

        // 列表变化
        viewModel.listUpdate
            .sink { [weak self] update in
                self?.applyListUpdate(update)
            }
            .store(in: &cancellables)

        // 置顶折叠条
        viewModel.$pinnedItems
            .sink { [weak self] items in
                self?.updatePinRail(items: items)
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
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                guard let self else { return }
                self.viewModel.updateFilter(state)
                self.updateFilterButtonAppearance()
                self.searchBar.updateTags(self.activeTags(for: state))
                self.syncTypeSegment(with: state)
                if state.isActive {
                    self.view.window?.makeFirstResponder(self.searchBar)
                }
                self.viewModel.performSearch(keyword: self.searchBar.text)
            }
            .store(in: &cancellables)
    }
}

// MARK: - 列表更新与选中

extension PasteMainViewController {
    private func applyListUpdate(_ update: PasteMainViewModel.ListUpdate) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(viewModel.items.map(\.hashValue))
        snapshot.reloadItems(update.reloaded)
        // 只换了置顶状态的卡片：先刷新图钉，再交给 diffable 做移动动画，其余内容不重配
        for model in update.pinChanged {
            if let indexPath = dataSource.indexPath(for: model.hashValue),
               let item = collectionView.item(at: indexPath) as? PasteCollectionViewItem {
                item.updatePinState(model: model)
            }
        }
        if update.animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dataSource.apply(snapshot, animatingDifferences: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshShortcutHints()
                    // 动画期间卡片还在移动，等落位后再把分组底色收拢到最后一张置顶卡
                    self?.updatePinnedGroupBackground()
                }
            }
        } else {
            dataSource.apply(snapshot, animatingDifferences: false)
            refreshShortcutHints()
        }

        let selected = viewModel.selectedIndexPath
        for indexPath in collectionView.indexPathsForVisibleItems() {
            collectionView.item(at: indexPath)?.isSelected = indexPath == selected
        }
        collectionView.selectionIndexPaths = viewModel.items.isEmpty ? [] : [selected]
        if update.scrollToBeginning {
            collectionView.scroll(.zero)
        } else if update.scrollToSelection {
            scrollTo(indexPath: selected)
        }
        if update.dataChanged {
            refreshTypeCounts()
        }
        updateEmptyState()
        updatePinnedGroupBackground()
    }

    private func makeItem(_ collectionView: NSCollectionView, at indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PasteCollectionViewItem.identifier, for: indexPath)
        guard let cItem = item as? PasteCollectionViewItem else { return item }
        cItem.delegate = self
        if let model = viewModel.item(at: indexPath) {
            cItem.updateItem(model: model)
        }
        if let flowLayout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            // itemSize.height 含上下阴影留白,扣除后才是卡片高度
            cItem.updateLayout(cardHeight: flowLayout.itemSize.height - Layout.itemShadowMargin * 2)
        }
        cItem.isSelected = viewModel.selectedIndexPath == indexPath
        return cItem
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

    private func updateEmptyState() {
        let isEmpty = viewModel.items.isEmpty
        emptyStateView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
        if isEmpty {
            let hasQuery = !searchBar.text.isEmpty || viewModel.filterIsActive
            emptyStateView.configure(hasQuery ? .noResults : .noHistory)
        }
    }
}

// MARK: - 数字快捷键

extension PasteMainViewController {
    private func setupKeyEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.setShortcutHintsVisible(flags == .command)
                self.setOptionHeld(flags == .option)
                PasteCollectionViewItem.refreshLinkCursor()
                return event
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let number = Self.shortcutNumber(for: event) {
                self.pasteShortcutItem(number)
                return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option,
               !self.viewModel.pinnedItems.isEmpty,
               let number = Self.shortcutNumber(for: event) {
                self.closePinPeek()
                self.viewModel.pastePinned(at: number - 1)
                return nil
            }
            if self.previewPopover?.isShown == true {
                switch Int(event.keyCode) {
                case kVK_Space, kVK_Escape:
                    self.closePreviewPopover()
                    return nil
                case kVK_LeftArrow, kVK_RightArrow:
                    self.closePreviewPopover()
                    return event
                default:
                    return event
                }
            }
            if !self.searchBar.isFirstResponder,
               KeyHelper.numberCharacters.contains(Int(event.keyCode)) {
                self.view.window?.makeFirstResponder(self.searchBar)
            }
            return event
        }
    }

    private static let digitKeyCodes: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    private static func shortcutNumber(for event: NSEvent) -> Int? {
        digitKeyCodes.firstIndex(of: Int(event.keyCode)).map { $0 + 1 }
    }

    /// 可见卡片按顺序编号 1–9
    private func visibleShortcutIndexPaths() -> [IndexPath] {
        let visibleRect = scrollView.contentView.bounds
        return collectionView.indexPathsForVisibleItems()
            .filter { indexPath in
                guard let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return false }
                // 只给露出一半以上的卡片编号
                return frame.intersection(visibleRect).width >= frame.width / 2
            }
            .sorted()
            .prefix(9)
            .map { $0 }
    }

    private func setShortcutHintsVisible(_ visible: Bool) {
        guard visible != isShowingShortcuts else { return }
        isShowingShortcuts = visible
        refreshShortcutHints()
    }

    private func refreshShortcutHints() {
        let numbered = isShowingShortcuts ? visibleShortcutIndexPaths() : []
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? PasteCollectionViewItem else { continue }
            item.setShortcutNumber(numbered.firstIndex(of: indexPath).map { $0 + 1 })
        }
    }

    private func pasteShortcutItem(_ number: Int) {
        let targets = visibleShortcutIndexPaths()
        guard number <= targets.count else { return }
        setShortcutHintsVisible(false)
        viewModel.pasteItem(at: targets[number - 1])
    }
}

// MARK: - 顶栏（类型分段、筛选、设置）

extension PasteMainViewController {
    private func typeSegmentChanged() {
        let index = typeSegment.selectedIndex
        guard Self.segmentTypes.indices.contains(index) else { return }
        filterView.setType(Self.segmentTypes[index])
    }

    /// 刷新分段按钮上的条数(全部 + PasteModelType.filterable 中的各类型)
    private func refreshTypeCounts() {
        Task {
            let counts = await viewModel.typeCounts()
            typeSegment.setCounts(Self.segmentTypes.map { $0.flatMap(counts.count(for:)) })
        }
    }

    private func syncTypeSegment(with state: FilterState) {
        typeSegment.selectedIndex = Self.segmentTypes.firstIndex(of: state.selectedType) ?? 0
    }

    private func showFilterPopover() {
        if filterPopover.isShown {
            filterPopover.close()
            return
        }
        Task {
            let apps = await viewModel.topApps()
            let allApps = await viewModel.allApps()
            filterView.configure(apps: apps, allApps: allApps)
            let btn = searchBar.filterButton
            filterPopover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .maxY)
        }
    }

    private func updateFilterButtonAppearance() {
        searchBar.filterButton.contentTintColor = viewModel.filterIsActive ? .controlAccentColor : .secondaryLabelColor
    }

    private func activeTags(for state: FilterState) -> [(text: String, icon: NSImage?)] {
        var tags: [(String, NSImage?)] = []
        if let app = state.selectedApp {
            var appIcon: NSImage?
            if let path = state.selectedAppPath {
                appIcon = NSWorkspace.shared.icon(forFile: path)
                appIcon?.size = NSSize(width: 14, height: 14)
            }
            tags.append((app, appIcon))
        }
        if let d = state.selectedDateRange { tags.append((d.title, nil)) }
        return tags
    }

    private func settingAction() {
        AppContext.coordinator.showSettings()
    }
}

// MARK: - 置顶折叠条

extension PasteMainViewController {
    private func setupPinRail() {
        // 分组底色的右边缘跟着置顶卡片走，横向滚动时要重算
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePinnedGroupBackground() }
        }
        pinRail.onClick = { [weak self] in
            guard let self else { return }
            self.closePinPeek()
            self.viewModel.togglePinsExpanded()
            self.updatePinRail(items: self.viewModel.pinnedItems)
        }
        pinRail.onHoverChange = { [weak self] hovered in
            guard let self else { return }
            self.isRailHovered = hovered
            if hovered {
                self.schedulePinPeek()
            } else {
                self.peekShowTask?.cancel()
                self.closePinPeekIfIdle()
            }
        }
    }

    private func updatePinRail(items: [PasteboardModel]) {
        let visible = !items.isEmpty
        pinRail.isHidden = !visible
        pinRail.configure(items: items, expanded: viewModel.pinsExpanded)
        // 收起和展开铺的是同一块底色（PinnedGroupBackgroundView），收起时只有竖条那么宽；
        // 展开时它连置顶卡片一起框住，列表自带的置顶分组底色就不用再画了
        let coversCards = visible && viewModel.pinsExpanded
        pinnedGroupBackground.isHidden = !visible
        if let layout = collectionView.collectionViewLayout as? PasteFlowLayout,
           layout.showsPinnedBackground != !coversCards {
            layout.showsPinnedBackground = !coversCards
            layout.invalidateLayout()
        }
        let leading = visible ? Layout.padding + PastePinRailView.width + PastePinRailView.gap - Layout.lineSpacing : 0
        scrollLeading?.update(offset: leading)
        updatePinnedGroupBackground()
        if !visible {
            closePinPeek()
        } else if let controller = pinPeekPopover?.contentViewController as? PastePinPeekViewController {
            controller.configure(items: items)
            pinPeekPopover?.contentSize = controller.preferredContentSize
        }
    }

    /// 竖条 + 置顶卡片的外接矩形，右边缘跟着最后一张置顶卡片走（横向滚动时实时更新）。
    /// 收起时只框住竖条，上下补到与装饰视图一样高，两种状态下底色完全一致
    private func updatePinnedGroupBackground() {
        guard !pinnedGroupBackground.isHidden, pinRail.frame.width > 0 else { return }
        var rect = pinRail.frame.insetBy(dx: 0, dy: -Layout.itemShadowMargin)
        if viewModel.pinsExpanded {
            // 只算列表开头连续的置顶卡片：展开刚触发、新数据还没回来时这里是 0，
            // 底色先跟竖条重合，不会错误地铺到普通卡片上
            let pinnedCount = viewModel.items.prefix { $0.isPinned }.count
            for index in 0..<pinnedCount {
                guard let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { continue }
                rect = rect.union(collectionView.convert(attributes.frame, to: contentView))
            }
        }
        // 置顶卡片滚出列表后不要把底色露到列表外面
        rect.size.width = max(0, min(rect.width, scrollView.frame.maxX - rect.minX))
        pinnedGroupBackground.frame = rect
    }

    private func schedulePinPeek() {
        peekShowTask?.cancel()
        peekShowTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.isRailHovered, !self.viewModel.pinsExpanded else { return }
            self.showPinPeek()
        }
    }

    private func setOptionHeld(_ held: Bool) {
        guard held != isOptionHeld else { return }
        isOptionHeld = held
        if held {
            showPinPeek()
        } else {
            closePinPeekIfIdle()
        }
    }

    private func showPinPeek() {
        guard pinPeekPopover?.isShown != true, !pinRail.isHidden, view.window?.isVisible == true else { return }
        let controller = PastePinPeekViewController()
        controller.configure(items: viewModel.pinnedItems)
        controller.onSelect = { [weak self] model in
            self?.closePinPeek()
            self?.viewModel.pasteModel(model, isOriginal: true)
        }
        controller.onHoverChange = { [weak self] hovered in
            self?.isPeekHovered = hovered
            if !hovered { self?.closePinPeekIfIdle() }
        }
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        pinPeekPopover = popover
        popover.show(relativeTo: pinRail.bounds, of: pinRail, preferredEdge: .maxX)
    }

    /// 鼠标从折叠条移到清单上要经过两者之间的空隙，稍等一下再判断是否真的离开了
    private func closePinPeekIfIdle() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !self.isRailHovered, !self.isPeekHovered, !self.isOptionHeld else { return }
            self.closePinPeek()
        }
    }

    private func closePinPeek() {
        peekShowTask?.cancel()
        isPeekHovered = false
        pinPeekPopover?.close()
        pinPeekPopover = nil
    }
}

// MARK: - 预览弹窗

extension PasteMainViewController {
    private func showPreviewPopover(for model: PasteboardModel, relativeTo view: NSView) {
        closePreviewPopover()
        let popover = PastePreviewPopover(model: model)
        popover.delegate = self
        previewPopover = popover
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    private func closePreviewPopover() {
        previewPopover?.close()
        previewPopover = nil
    }
}

// MARK: - 拖动调整面板高度

extension PasteMainViewController {
    private func setupResizeHandle() {
        resizeHandle.onResize = { [weak self] targetHeight in
            guard let self, let window = self.view.window else { return }
            var frame = window.frame

            let newHeight: CGFloat
            if targetHeight > Layout.maxViewHeight {
                let overflow = (targetHeight - Layout.maxViewHeight) * 0.05
                newHeight = Layout.maxViewHeight + overflow
            } else if targetHeight < Layout.minViewHeight {
                let overflow = (Layout.minViewHeight - targetHeight) * 0.05
                newHeight = Layout.minViewHeight - overflow
            } else {
                newHeight = targetHeight
            }

            frame.size.height = newHeight + Layout.panelShadowMargin * 2
            window.setFrame(frame, display: true)
            self.updateItemSize(for: newHeight)
            Log("Panel height: \(newHeight)")
        }
        resizeHandle.onResizeEnd = { [weak self] in
            guard let self, let window = self.view.window else { return }
            let currentHeight = Self.panelHeight(of: window)
            let clampedHeight = min(max(currentHeight, Layout.minViewHeight), Layout.maxViewHeight)
            if currentHeight != clampedHeight {
                self.isBouncingBack = true
                var frame = window.frame
                frame.size.height = clampedHeight + Layout.panelShadowMargin * 2
                Task {
                    await NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.15
                        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        window.animator().setFrame(frame, display: true)
                    }
                    self.isBouncingBack = false
                }
            }
            PasteUserDefaults.panelHeight = Double(clampedHeight)
        }
    }

    /// 面板本身的高度：窗口高度去掉上下的阴影边距
    private static func panelHeight(of window: NSWindow) -> CGFloat {
        window.frame.height - Layout.panelShadowMargin * 2
    }

    private func updateItemSize(for height: CGFloat) {
        guard let flowLayout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }

        // resize 会改变 item 宽度→内容总宽变化,记录当前横向滚动进度比例,重排后按比例还原,
        // 避免拖动高度时列表横向跳动。
        let clipView = scrollView.contentView
        let oldScrollableWidth = collectionView.bounds.width - clipView.bounds.width
        let scrollProgress = oldScrollableWidth > 0 ? clipView.bounds.origin.x / oldScrollableWidth : 0

        let newSize = Layout.dynamicItemSize(for: height)
        flowLayout.itemSize = newSize
        flowLayout.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()

        // 按原进度比例还原横向偏移
        let newScrollableWidth = collectionView.bounds.width - clipView.bounds.width
        if newScrollableWidth > 0 {
            let restoredX = min(max(scrollProgress * newScrollableWidth, 0), newScrollableWidth)
            clipView.scroll(to: NSPoint(x: restoredX, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
        }

        // 卡片高度(扣除上下阴影留白),topView 比例/字号/compact 判断都按卡片高
        let cardHeight = newSize.height - Layout.itemShadowMargin * 2
        for indexPath in collectionView.indexPathsForVisibleItems() {
            if let item = collectionView.item(at: indexPath) as? PasteCollectionViewItem {
                item.updateLayout(cardHeight: cardHeight)
            }
        }
    }
}

// MARK: - PasteCollectionViewKeyDelegate

extension PasteMainViewController: PasteCollectionViewKeyDelegate {
    func collectionViewDidPressEscape() {
        if previewPopover?.isShown == true {
            closePreviewPopover()
        } else if filterPopover.isShown {
            filterPopover.close()
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

    func collectionViewDidPressDelete() {
        viewModel.deleteItem(at: viewModel.selectedIndexPath)
    }

    func collectionViewDidPressReturn() {
        viewModel.pasteItem(at: viewModel.selectedIndexPath)
    }

    func collectionViewDidPressSpace() {
        guard let model = viewModel.item(at: viewModel.selectedIndexPath),
              let itemView = collectionView.item(at: viewModel.selectedIndexPath)?.view else { return }
        showPreviewPopover(for: model, relativeTo: itemView)
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

    func copyOCRText(_ item: PasteboardModel) {
        viewModel.copyOCRText(from: item)
    }

    func pasteOCRText(_ item: PasteboardModel) {
        viewModel.pasteOCRText(from: item)
    }

    func togglePin(_ item: PasteboardModel) {
        viewModel.togglePin(for: item)
    }
}

// MARK: - NSSearchFieldDelegate

extension PasteMainViewController: NSSearchFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        view.window?.makeFirstResponder(collectionView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if filterPopover.isShown {
                filterPopover.close()
                return true
            }
            let needRefresh = !searchBar.text.isEmpty || viewModel.filterIsActive
            searchBar.stringValue = ""
            filterView.resetFilter()
            viewModel.updateFilter(.empty)
            updateFilterButtonAppearance()
            searchBar.updateTags([])
            view.window?.makeFirstResponder(collectionView)
            if needRefresh {
                viewModel.resetToDefaultList()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            if textView.string.isEmpty && viewModel.filterIsActive {
                viewModel.removeLastFilterTag(from: filterView)
                return true
            }
        }
        return false
    }
}

// MARK: - NSPopoverDelegate

extension PasteMainViewController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === previewPopover {
            previewPopover = nil
        }
    }
}
