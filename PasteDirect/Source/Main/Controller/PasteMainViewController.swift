//
//  PasteMainViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import AppKit
import Carbon
import Cocoa
import RxCocoa
import RxSwift
import SnapKit

final class PasteMainViewController: NSViewController {
    private var selectIndexPath = IndexPath(item: 0, section: 0)
    private var dataList = PasteDataStore.main.dataList
    private let disposeBag = DisposeBag()
    private var deleteItem = false

    // MARK: - lazy property

    private lazy var collectionView = NSCollectionView().then {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = Layout.itemSize
        flowLayout.minimumLineSpacing = Layout.lineSpacing
        flowLayout.scrollDirection = .horizontal
        flowLayout.headerReferenceSize = Layout.headerFooterSize
        flowLayout.footerReferenceSize = Layout.headerFooterSize
        flowLayout.sectionInset = NSEdgeInsets(top: 0, left: Layout.lineSpacing, bottom: 0, right: Layout.lineSpacing)
        $0.frame = view.bounds
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
        let clipView = NSClipView(frame: view.bounds)
        clipView.documentView = collectionView
        $0.contentView = clipView
        $0.scrollerStyle = .overlay
        $0.horizontalScrollElasticity = .automatic
        $0.autoresizingMask = [.width, .height]
        $0.scrollerInsets = Layout.edgeInsets
        $0.delegate = self
    }

    private lazy var effectView: NSView = {
        if #available(macOS 26.0, *) {
           let effectView = NSGlassEffectView()
            effectView.frame = view.frame
            effectView.cornerRadius = 0
            return effectView
        } else {
           let effectView = NSVisualEffectView()
            effectView.frame = view.frame
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            return effectView
        }
    }()

    private lazy var searchBar = PasteSearchField().then {
        $0.cell?.controlSize = .large
        $0.focusRingType = .none
        $0.refusesFirstResponder = true
        $0.placeholderString = "搜索"
        $0.delegate = self
    }
}

// MARK: - 生命周期

extension PasteMainViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        initRx()
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
        PasteDataStore.main.clearExpiredData()
    }
}

// MARK: - UI & Rx

extension PasteMainViewController {
    private func initSubviews() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.maskedCorners = CACornerMask([.layerMaxXMaxYCorner, .layerMinXMaxYCorner])
        view.layer?.masksToBounds = true
        view.layer?.cornerRadius = 34
        view.addSubview(effectView)
        view.addSubview(scrollView)
        view.addSubview(searchBar)
        effectView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        scrollView.contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalToSuperview().offset(50)
        }
        searchBar.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.greaterThanOrEqualTo(view).offset(5)
            make.bottom.greaterThanOrEqualTo(scrollView.snp.top).offset(-5)
            make.height.equalTo(Layout.searchBarHeight)
            make.width.equalTo(Layout.searchBarWidth)
        }
    }

    private func initRx() {
        searchBar.rx.text.orEmpty
            .skip(1)
            .debounce(.milliseconds(200), scheduler: MainScheduler.instance)
            .subscribe(
                with: self,
                onNext: { wrapper, text in
                    wrapper.scrollView.isSearching = !text.isEmpty
                    wrapper.searchWord(text)
                }
            )
            .disposed(by: disposeBag)

        dataList.observe(on: MainScheduler.instance)
            .filter { [weak self] _ in self?.deleteItem == false }
            .subscribe(
                with: self,
                onNext: { wrapper, _ in
                    wrapper.deleteItem = false
                    wrapper.scrollView.isLoding = false
                    wrapper.collectionView.reloadData()
                }
            ).disposed(by: disposeBag)
    }
}

// MARK: - 私有方法

extension PasteMainViewController {
    private func searchWord(_ keyword: String) {
        if keyword.isEmpty {
            resetToDefaultList()
        } else {
            resetSelectIndex()
            PasteDataStore.main.searchData(keyword)
            Log("search start: \(keyword)")
            collectionView.scroll(.zero)
        }
    }

    private func resetToDefaultList() {
        scrollView.resetState()
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
        if searchBar.isFirstResponder {
            searchBar.objectValue = nil
            view.window?.makeFirstResponder(collectionView)
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
            collectionView.selectItems(at: [selectIndexPath], scrollPosition: .nearestVerticalEdge)
        }
    }
}

// MARK: - NSCollectionViewDelegate

extension PasteMainViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        if let indexPath = indexPaths.first {
            selectIndexPath = indexPath
        }
        Log("选中\(indexPaths.description)")
        return indexPaths
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
        if dataList.value.count >= PasteDataStore.main.totalCount.value {
            scrollView.noMore = true
            scrollView.isLoding = false
            return
        }
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
}
