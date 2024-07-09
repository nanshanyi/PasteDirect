//
//  PasteMainViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import AppKit
import Carbon
import Cocoa
import SnapKit
import RxSwift
import RxCocoa

class PasteMainViewController: NSViewController {
    private let viewHeight: CGFloat = 360
    private var selectIndex: IndexPath = .init(item: 0, section: 0)
    private var dataList = [PasteboardModel]()
    private let disposeBag = DisposeBag()
    public var frame: NSRect {
        didSet {
            reLayoutFrame()
        }
    }

    init(_ f: NSRect? = nil) {
        frame = f ?? NSRect(x: 0, y: 0, width: 2000, height: viewHeight)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func vcDismiss(completionHandler: (() -> Void)? = nil) {
        if searchBar.isEditing {
            searchBar.abortEditing()
            searchBar.resignFirstResponder()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.view.animator().setFrameOrigin(NSPoint(x: 0, y: -view.bounds.height))
        }, completionHandler: completionHandler)
    }

    // MARK: - lazy property

    private lazy var collectionView = NSCollectionView().then {
        let flowLayout = NSCollectionViewFlowLayout()
        let height = 280
        flowLayout.itemSize = NSSize(width: height, height: height)
        flowLayout.minimumLineSpacing = 20
        flowLayout.scrollDirection = .horizontal
        flowLayout.headerReferenceSize = NSSize(width: 20, height: height)
        flowLayout.footerReferenceSize = NSSize(width: 20, height: height)
        $0.frame = self.view.bounds
        $0.wantsLayer = true
        $0.delegate = self
        $0.dataSource = self
        $0.backgroundColors = [.clear]
        $0.collectionViewLayout = flowLayout
        $0.isSelectable = true
        $0.register(PasteCollectionViewItem.self)
    }

    private lazy var scrollView = PasteScrollView().then {
        let clipView = NSClipView(frame: self.view.bounds)
        clipView.documentView = collectionView
        $0.contentView = clipView
        $0.scrollerStyle = .overlay
        $0.horizontalScrollElasticity = .automatic
        $0.autoresizingMask = [.width, .height]
        $0.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: -100, right: 0)
        $0.delegate = self
    }

    private lazy var effectView = NSVisualEffectView().then {
        $0.frame = self.view.frame
        $0.state = .active
        $0.blendingMode = .behindWindow
    }

    private lazy var searchBar = PasteSearchField().then {
        $0.wantsLayer = true
        $0.layer?.masksToBounds = true
        $0.layer?.borderWidth = 1
        $0.layer?.borderColor = NSColor.lightGray.cgColor
        $0.layer?.cornerRadius = 15
        $0.focusRingType = .none
        $0.delegate = self
        $0.refusesFirstResponder = true
        $0.placeholderString = "搜索"
    }
}

// MARK: - lifeCycle

extension PasteMainViewController {
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: viewHeight))
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        initRx()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: keyDownEvent(_:))
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        searchBar.objectValue = nil
        view.window?.makeFirstResponder(collectionView)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        searchBar.isHidden = true
        PasteDataStore.main.clearExpiredData()
    }

    override func viewDidAppear() {
        scrollView.isSearching = false
        searchBar.isHidden = false
        view.window?.makeFirstResponder(collectionView)
        view.frame = NSRect(x: view.frame.origin.x, y: -viewHeight, width: frame.width, height: viewHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.view.animator().setFrameOrigin(.zero)
        }
        if PasteDataStore.main.dataChange {
            dataList = PasteDataStore.main.dataList
            collectionView.reloadData()
            PasteDataStore.main.dataChange.toggle()
            selectIndex = IndexPath(item: 0, section: 0)
            collectionView.selectItems(at: [selectIndex], scrollPosition: .left)
        }
    }
}

// MARK: - UI

extension PasteMainViewController {
    private func initSubviews() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(effectView)
        view.addSubview(scrollView)
        view.addSubview(searchBar)
        reLayoutFrame()
    }

    private func reLayoutFrame() {
        effectView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        scrollView.contentView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        scrollView.snp.remakeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(view).offset(50)
        }
        searchBar.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.greaterThanOrEqualTo(view).offset(5)
            make.bottom.greaterThanOrEqualTo(scrollView.snp.top).offset(-5)
            make.height.equalTo(30)
            make.width.equalTo(200)
        }
    }
    
    private func initRx() {
        searchBar.rx.text.orEmpty
            .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
            .subscribe(
                with: self,
                onNext: { wrapper, text in
                    wrapper.scrollView.isSearching = true
                    if text.isEmpty {
                        wrapper.resetToDefaultList()
                    } else {
                        wrapper.searchWord()
                    }
                }
            )
            .disposed(by: disposeBag)
    }
}

// MARK: - 私有方法

extension PasteMainViewController {
    private func searchWord() {
        let keyWord = searchBar.stringValue
        selectIndex = IndexPath(item: 0, section: 0)
        Log("search start: \(keyWord)")
        Task {
            dataList = await PasteDataStore.main.searchData(keyWord)
            collectionView.reloadData()
            if !dataList.isEmpty {
                collectionView.selectItems(at: [selectIndex], scrollPosition: .left)
            }
            Log("search result: \(dataList.count) word: \(keyWord)")
        }
    }

    private func resetToDefaultList() {
        scrollView.isSearching = false
        dataList = PasteDataStore.main.dataList
        collectionView.reloadData()
        if !dataList.isEmpty {
            collectionView.selectItems(at: [selectIndex], scrollPosition: .left)
        }
    }

    private func keyDownEvent(_ event: NSEvent) -> NSEvent? {
        if KeyHelper.numberChacraer.contains(where: { $0 == event.keyCode }) {
            if !searchBar.isFirstResponder {
                view.window?.makeFirstResponder(searchBar)
            }
        } else if event.keyCode == kVK_Escape {
            if searchBar.isFirstResponder {
                searchBar.objectValue = nil
                view.window?.makeFirstResponder(collectionView)
                resetToDefaultList()
                return nil
            } else {
                let app = NSApplication.shared.delegate as? PasteAppDelegate
                app?.mainWindowController.dismissWindow()
            }
        }
        return event
    }
}

// MARK: - NSCollectionViewDelegate

extension PasteMainViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        if let indexPath = indexPaths.first {
            selectIndex = indexPath
        }
        Log("选中\(indexPaths.description)")
        return indexPaths
    }
}

// MARK: - NSCollectionViewDataSource

extension PasteMainViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataList.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PasteCollectionViewItem.identifier, for: indexPath)
        guard let cItem = item as? PasteCollectionViewItem else { return item }
        cItem.delegate = self
        cItem.updateItem(model: dataList[indexPath.item])
        return cItem
    }
}

// MARK: - NSSearchFieldDelegate

extension PasteMainViewController: NSSearchFieldDelegate {}

// MARK: - PasteScrollViewDelegate

extension PasteMainViewController: PasteScrollViewDelegate {
    func loadMoreData() {
        if dataList.count >= PasteDataStore.main.totoalCount.value {
            scrollView.noMore = true
            scrollView.isLoding = false
            return
        }
        Task {
            dataList = await PasteDataStore.main.loadNextPage()
            collectionView.reloadData()
            scrollView.isLoding = false
        }
    }
}

// MARK: - PasteCollectionViewItemDelegate

extension PasteMainViewController: PasteCollectionViewItemDelegate {
    func deleteItem(_ item: PasteboardModel, indePath: IndexPath) {
        PasteDataStore.main.deleteItem(item)
        dataList.removeAll(where: { $0 == item })
        collectionView.animator().deleteItems(at: [indePath])
    }
}
