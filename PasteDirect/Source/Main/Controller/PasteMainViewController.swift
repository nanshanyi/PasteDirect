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
        $0.register(PinRailHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    withIdentifier: PinRailHeaderView.identifier)
        $0.registerForDraggedTypes(PasteboardType.supportTypes)
        $0.setDraggingSourceOperationMask(.every, forLocal: true)
        $0.setDraggingSourceOperationMask(.every, forLocal: false)
    }

    /// 以条目 hash 为标识，列表变化时自动计算插入/删除/移动动画
    private lazy var dataSource = NSCollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { [weak self] collectionView, indexPath, _ in
        self?.makeItem(collectionView, at: indexPath)
    }.then {
        // 置顶折叠条是 section header：每次取到的容器可能是新建的，把同一个竖条放进去
        $0.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self, kind == NSCollectionView.elementKindSectionHeader,
                  let header = collectionView.makeSupplementaryView(
                      ofKind: kind, withIdentifier: PinRailHeaderView.identifier, for: indexPath) as? PinRailHeaderView
            else { return nil }
            header.embed(self.pinRail)
            return header
        }
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

    private var pinPeekPopover: NSPopover?
    private var isRailHovered = false
    private var isPeekHovered = false
    /// 按住 ⌥ 时弹出置顶清单显示 ⌥1–9
    private var isOptionHeld = false
    /// 展开/收起的动画参数：设计稿的 .32s cubic-bezier(.3,.7,.2,1)
    private static let pinsToggleDuration: TimeInterval = 0.32
    private static let pinsToggleTiming = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1)
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
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // 每次打开面板回到设置里的默认展开状态；窗口还没显示，切换不做动画
        viewModel.applyDefaultPinsExpansion()
    }

    /// 面板显示时默认获得焦点的视图
    var initialFirstResponder: NSView { collectionView }

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
        // 走 setOptionHeld：关面板时还按着 ⌥，卡片上的 ⌥ 角标要一起收掉
        setOptionHeld(false)
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
        // 置顶折叠条和分组底色都在列表里（section header + 装饰视图），这里不用单独加
        contentView.addSubview(scrollView)
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
            make.leading.trailing.equalToSuperview()
            // 上下各收 itemShadowMargin,抵消卡片内缩带来的额外间距,回到原视觉间距
            make.bottom.equalToSuperview().offset(-Layout.scrollViewBottom + Layout.itemShadowMargin)
            make.top.equalTo(searchBar.snp.bottom).offset(Layout.scrollViewTop - Layout.itemShadowMargin)
        }

        emptyStateView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView)
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
        if update.pinsToggled {
            // 竖条外观、header 悬停开关和新数据在同一次更新里切换，不会出现新旧状态混在一起的一帧；
            // 底色是装饰视图，和卡片在下面这次快照动画里一起伸缩
            updatePinRail(items: viewModel.pinnedItems, animated: update.animated)
        }
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
        if update.scrollToBeginning {
            // 先回到开头、把开头的卡片建好，再换数据：动画是按换数据那一刻的可见区域算的。
            // 滚远了再换，开头那批卡片在动画开始时还不存在，回到开头后要等动画结束才出来，中间是空白
            collectionView.scroll(.zero)
            collectionView.layoutSubtreeIfNeeded()
        }
        if update.animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = update.pinsToggled ? Self.pinsToggleDuration : 0.35
                ctx.timingFunction = update.pinsToggled ? Self.pinsToggleTiming : CAMediaTimingFunction(name: .easeInEaseOut)
                dataSource.apply(snapshot, animatingDifferences: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshShortcutHints()
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
            // 换完数据再对齐一次：新列表变短时，前面那次滚动位置可能已经超出内容
            collectionView.scroll(.zero)
        } else if update.scrollToSelection {
            scrollTo(indexPath: selected)
        }
        if update.dataChanged {
            refreshTypeCounts()
        }
        updateEmptyState()
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
        guard let item = collectionView.layoutAttributesForItem(at: indexPath),
              let layout = collectionView.collectionViewLayout as? PasteFlowLayout else { return }
        // 左边留出的距离：竖条悬停时要躲开它，卡片停在和列表开头一样的位置；
        // 展开时第一张卡片前面是竖条，直接滚到最开头，不要把竖条切掉一半
        let leadingRoom = layout.hasPinRail && layout.pinsRail
            ? layout.headerReferenceSize.width + layout.sectionInset.left
            : Layout.lineSpacing
        let minX = indexPath.item == 0 ? 0 : max(0, item.frame.minX - leadingRoom)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            collectionView.animator().scrollToVisible(NSRect(x: minX, y: 0, width: item.frame.maxX + Layout.lineSpacing - minX, height: item.frame.height))
        }
    }

    private func updateEmptyState() {
        // 竖条在列表里：只要还有置顶（全部记录都置顶、收起时列表是空的），列表就得留着
        let isEmpty = viewModel.items.isEmpty && pinRail.isHidden
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
            // 本地监听收得到本 app 所有窗口的按键。面板启动时就创建了，没打开时不处理，
            // 否则在设置窗口里按 ⌘1 也会触发粘贴
            guard let self, self.view.window?.isVisible == true else { return event }
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

    /// ⌘1–9：可见的未置顶卡片按顺序编号。置顶卡片归 ⌥1–9（按置顶顺序），两套编号不重叠
    private func visibleShortcutIndexPaths() -> [IndexPath] {
        let visibleRect = scrollView.contentView.bounds
        return collectionView.indexPathsForVisibleItems()
            .filter { indexPath in
                // 有折叠条时置顶卡片走 ⌥；搜索、筛选时没有折叠条，置顶卡片照常参与 ⌘ 编号
                if !self.pinRail.isHidden, self.viewModel.item(at: indexPath)?.isPinned == true { return false }
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

    /// 展开时按住 ⌥：置顶卡片直接显示 ⌥1–9，不弹清单
    private var showsPinnedShortcutBadges: Bool {
        isOptionHeld && viewModel.pinsExpanded && !pinRail.isHidden
    }

    private func refreshShortcutHints() {
        let numbered = isShowingShortcuts ? visibleShortcutIndexPaths() : []
        // 编号和折叠条、清单一致：第 N 条置顶就是 ⌥N
        let pinnedNumbers: [Int: Int] = showsPinnedShortcutBadges
            ? Dictionary(uniqueKeysWithValues: viewModel.pinnedItems.prefix(9).enumerated().map { ($1.hashValue, $0 + 1) })
            : [:]
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? PasteCollectionViewItem else { continue }
            if let hash = viewModel.item(at: indexPath)?.hashValue, let number = pinnedNumbers[hash] {
                item.setShortcutNumber(number, modifier: "⌥")
            } else {
                item.setShortcutNumber(numbered.firstIndex(of: indexPath).map { $0 + 1 })
            }
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
        pinRail.onClick = { [weak self] in
            guard let self else { return }
            self.closePinPeek()
            // 新列表同步发出，竖条和底色在 applyListUpdate 里跟着一起切换
            self.viewModel.togglePinsExpanded()
            // 收起后鼠标还停在竖条上：不会再收到进入事件，主动把清单再弹出来，和收起动画同时开始
            if !self.viewModel.pinsExpanded, self.isRailHovered {
                self.showPinPeek()
            }
        }
        pinRail.onHoverChange = { [weak self] hovered in
            guard let self else { return }
            self.isRailHovered = hovered
            self.updatePinnedGroupDimming()
            if hovered {
                // 展开时置顶卡片就在旁边，不需要清单
                if !self.viewModel.pinsExpanded { self.showPinPeek() }
            } else {
                self.closePinPeekIfIdle()
            }
        }
    }

    private func updatePinRail(items: [PasteboardModel], animated: Bool = true) {
        let visible = !items.isEmpty
        pinRail.isHidden = !visible
        pinRail.configure(items: items, expanded: viewModel.pinsExpanded, animated: animated)
        if let layout = collectionView.collectionViewLayout as? PasteFlowLayout {
            layout.hasPinRail = visible
            // 收起时竖条悬停在左边，卡片从它下面滑过；展开时竖条跟着列表滑走
            layout.pinsRail = !viewModel.pinsExpanded
        }
        updatePinnedGroupDimming()
        // 全部记录都置顶、收起时列表是空的：有竖条就不显示空状态
        updateEmptyState()
        if !visible {
            closePinPeek()
        } else if let controller = pinPeekPopover?.contentViewController as? PastePinPeekViewController {
            controller.configure(items: items)
            pinPeekPopover?.contentSize = controller.preferredContentSize
        }
    }

    /// 收起时底色平时用淡色，鼠标在竖条上才加深；展开时连着卡片，一直用常规色
    private func updatePinnedGroupDimming() {
        (collectionView.collectionViewLayout as? PasteFlowLayout)?.dimsPinnedBackground =
            !viewModel.pinsExpanded && !isRailHovered
    }

    private func setOptionHeld(_ held: Bool) {
        guard held != isOptionHeld else { return }
        isOptionHeld = held
        // 展开时置顶卡片就在列表里，直接在卡片上显示 ⌥1–9；收起时才弹清单
        refreshShortcutHints()
        if held {
            if !viewModel.pinsExpanded { showPinPeek() }
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
        // 展开后竖条可能已经跟着列表滚出去了（按住 ⌥ 时），这时把清单挂到列表左边缘
        let railVisible = pinRail.window != nil && !pinRail.visibleRect.isEmpty
        if railVisible {
            popover.show(relativeTo: pinRail.bounds, of: pinRail, preferredEdge: .maxX)
        } else {
            let anchor = NSRect(x: 0, y: 0, width: Layout.padding, height: scrollView.bounds.height)
            popover.show(relativeTo: anchor, of: scrollView, preferredEdge: .maxX)
        }
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
