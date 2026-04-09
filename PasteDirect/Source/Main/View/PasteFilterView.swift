//
//  PasteFilterView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/04/08.
//

import AppKit
import Combine

// MARK: - FilterState

enum DateRange: String, CaseIterable {
    case today = "今天"
    case yesterday = "昨天"
    case thisWeek = "本周"
    case lastWeek = "上周"
    case last30Days = "最近 30 天"

    var dateInterval: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return (todayStart, now)
        case .yesterday:
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            return (yesterdayStart, todayStart)
        case .thisWeek:
            let weekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: now).date!
            return (weekStart, now)
        case .lastWeek:
            let thisWeekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: now).date!
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            return (lastWeekStart, thisWeekStart)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (start, now)
        }
    }
}

struct FilterState: Equatable {
    var selectedApp: String?
    var selectedAppPath: String?
    var selectedType: PasteModelType?
    var selectedDateRange: DateRange?

    var isActive: Bool {
        selectedApp != nil || selectedType != nil || selectedDateRange != nil
    }

    var activeTags: [(text: String, icon: NSImage?)] {
        var tags: [(String, NSImage?)] = []
        if let app = selectedApp {
            var appIcon: NSImage?
            if let path = selectedAppPath {
                appIcon = NSWorkspace.shared.icon(forFile: path)
                appIcon?.size = NSSize(width: 14, height: 14)
            }
            tags.append((app, appIcon))
        }
        if let t = selectedType { tags.append((t.string, nil)) }
        if let d = selectedDateRange { tags.append((d.rawValue, nil)) }
        return tags
    }

    static let empty = FilterState()
}

// MARK: - Section / Item Model

private enum FilterSection: Int, CaseIterable {
    case app = 0, type, date

    var title: String {
        switch self {
        case .app: return "应用"
        case .type: return "类型"
        case .date: return "日期"
        }
    }
}

private struct FilterItemModel {
    let title: String
    let icon: NSImage?
    var isOn: Bool
    let isMoreButton: Bool

    init(title: String, icon: NSImage? = nil, isOn: Bool = false, isMoreButton: Bool = false) {
        self.title = title
        self.icon = icon
        self.isOn = isOn
        self.isMoreButton = isMoreButton
    }
}

// MARK: - Header View

private final class FilterHeaderView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("FilterHeaderView")

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.stringValue = title
    }
}

// MARK: - Left-Aligned Flow Layout

private final class LeftAlignedFlowLayout: NSCollectionViewFlowLayout {

    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []

    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        let fullRect = NSRect(origin: .zero, size: collectionViewContentSize)
        let allAttrs = super.layoutAttributesForElements(in: fullRect).map { $0.copy() as! NSCollectionViewLayoutAttributes }

        var leftMargin = sectionInset.left
        var lastY: CGFloat = -.greatestFiniteMagnitude

        for attr in allAttrs {
            if attr.representedElementCategory == .supplementaryView { continue }
            if attr.frame.origin.y > lastY + 1 {
                leftMargin = sectionInset.left
                lastY = attr.frame.origin.y
            }
            attr.frame.origin.x = leftMargin
            leftMargin += attr.frame.width + minimumInteritemSpacing
        }
        cachedAttributes = allAttrs
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cachedAttributes.first {
            $0.representedElementCategory == .item && $0.indexPath == indexPath
        }
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cachedAttributes.first {
            $0.representedElementCategory == .supplementaryView && $0.indexPath == indexPath
        }
    }
}

// MARK: - PasteFilterView

final class PasteFilterView: NSView {

    @Published private(set) var filterState = FilterState.empty

    private var apps: [(name: String, path: String)] = []
    private var allApps: [(name: String, path: String)] = []
    private var showingAllApps = false

    static let contentWidth: CGFloat = 350

    private var sectionItems: [[FilterItemModel]] = [[], [], []]

    private lazy var flowLayout: LeftAlignedFlowLayout = {
        let layout = LeftAlignedFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = NSEdgeInsets(top: 0, left: 16, bottom: 8, right: 16)
        layout.headerReferenceSize = NSSize(width: Self.contentWidth, height: 28)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        return layout
    }()

    private lazy var collectionView: NSCollectionView = {
        let cv = NSCollectionView()
        cv.collectionViewLayout = flowLayout
        cv.dataSource = self
        cv.delegate = self
        cv.backgroundColors = [.clear]
        cv.isSelectable = false
        cv.register(PasteFilterItem.self)
        cv.register(FilterHeaderView.self,
                    forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    withIdentifier: FilterHeaderView.identifier)
        return cv
    }()

    private lazy var scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.documentView = collectionView
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        sv.drawsBackground = false
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return sv
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        // 给 collectionView 正确的宽度，高度由内容决定
        let cvHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? bounds.height
        collectionView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(cvHeight, bounds.height))
    }

    func configure(apps: [(name: String, path: String)], allApps: [(name: String, path: String)]) {
        self.apps = apps
        self.allApps = allApps
        self.showingAllApps = false
        rebuildData()
    }

    // MARK: - Data

    private func rebuildData() {
        let list = showingAllApps ? allApps : apps
        var appItems: [FilterItemModel] = list.map { app in
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            return FilterItemModel(title: app.name, icon: icon, isOn: filterState.selectedApp == app.name)
        }
        if allApps.count > apps.count && !showingAllApps {
            let moreIcon = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
            appItems.append(FilterItemModel(title: "更多", icon: moreIcon, isMoreButton: true))
        }

        let types: [(String, String, PasteModelType)] = [
            ("文本", "doc.text", .string),
            ("图片", "photo", .image),
            ("颜色", "paintpalette", .color),
        ]
        let typeItems: [FilterItemModel] = types.map {
            FilterItemModel(title: $0.0,
                            icon: NSImage(systemSymbolName: $0.1, accessibilityDescription: nil),
                            isOn: filterState.selectedType == $0.2)
        }

        let dateItems: [FilterItemModel] = DateRange.allCases.map {
            FilterItemModel(title: $0.rawValue,
                            icon: NSImage(systemSymbolName: "calendar", accessibilityDescription: nil),
                            isOn: filterState.selectedDateRange == $0)
        }

        sectionItems = [appItems, typeItems, dateItems]
        collectionView.reloadData()

        // reload 后重新计算 collectionView 高度
        collectionView.layoutSubtreeIfNeeded()
        let cvHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        collectionView.setFrameSize(NSSize(width: bounds.width, height: max(cvHeight, bounds.height)))
    }

    // MARK: - Actions

    private func appTapped(_ idx: Int) {
        let list = showingAllApps ? allApps : apps
        guard idx < list.count else { return }
        let app = list[idx]
        if filterState.selectedApp == app.name {
            filterState.selectedApp = nil
            filterState.selectedAppPath = nil
        } else {
            filterState.selectedApp = app.name
            filterState.selectedAppPath = app.path
        }
        rebuildData()
    }

    private func typeTapped(_ idx: Int) {
        let types: [PasteModelType] = [.string, .image, .color]
        let t = types[idx]
        filterState.selectedType = (filterState.selectedType == t) ? nil : t
        rebuildData()
    }

    private func dateTapped(_ idx: Int) {
        let d = DateRange.allCases[idx]
        filterState.selectedDateRange = (filterState.selectedDateRange == d) ? nil : d
        rebuildData()
    }

    private func moreTapped() {
        showingAllApps = true
        rebuildData()
    }

    func resetFilter() {
        filterState = .empty
        showingAllApps = false
        rebuildData()
    }

    enum FilterKind { case app, type, date }

    func removeFilter(_ kind: FilterKind) {
        switch kind {
        case .app:
            filterState.selectedApp = nil
            filterState.selectedAppPath = nil
        case .type:
            filterState.selectedType = nil
        case .date:
            filterState.selectedDateRange = nil
        }
        rebuildData()
    }
}

// MARK: - NSCollectionViewDataSource

extension PasteFilterView: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        FilterSection.allCases.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sectionItems[section].count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PasteFilterItem.identifier, for: indexPath) as! PasteFilterItem
        let model = sectionItems[indexPath.section][indexPath.item]
        item.configure(title: model.title, icon: model.icon, isOn: model.isOn)

        let section = FilterSection(rawValue: indexPath.section)!
        let idx = indexPath.item
        item.onClick = { [weak self] in
            guard let self else { return }
            if model.isMoreButton {
                self.moreTapped()
                return
            }
            switch section {
            case .app: self.appTapped(idx)
            case .type: self.typeTapped(idx)
            case .date: self.dateTapped(idx)
            }
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView,
                         viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                         at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: FilterHeaderView.identifier,
            for: indexPath) as! FilterHeaderView
        let section = FilterSection(rawValue: indexPath.section)!
        header.configure(title: section.title)
        return header
    }
}

// MARK: - NSCollectionViewDelegateFlowLayout

extension PasteFilterView: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView,
                        layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        let model = sectionItems[indexPath.section][indexPath.item]
        let textWidth = (model.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        let hasIcon = model.icon != nil
        let w = ceil((hasIcon ? 28 : 10) + textWidth + 10)
        let maxW = Self.contentWidth - 32
        return NSSize(width: min(w, maxW), height: 28)
    }
}
