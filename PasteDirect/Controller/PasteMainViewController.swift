//
//  PasteMainViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Cocoa
import AppKit
import SnapKit

class PasteMainViewController: NSViewController {

    let viewHeight: CGFloat = 360
    var selectIndex: IndexPath = IndexPath(item: 0, section: 0)
    var searchBar: NSSearchField
    var dataList = [PasteboardModel]()
    var frame: NSRect {
        didSet {
            reLayoutFrame()
        }
    }
    
    init(_ f: NSRect? = nil) {
        searchBar = NSSearchField()
        frame = f ?? NSRect(x: 0, y: 0, width: 2000, height: viewHeight)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: viewHeight))
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(veView)
        view.addSubview(scrollView)
        searchBar.delegate = self
        searchBar.refusesFirstResponder = true
        searchBar.placeholderString = "搜索"
        view.addSubview(searchBar)
        reLayoutFrame()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        searchBar.objectValue = nil
        searchBar.endEditing(NSText())

    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        searchBar.isHidden = true
    }
    
    override func viewDidAppear() {
        scrollView.isSearching = false
        searchBar.isHidden = false
        searchBar.resignFirstResponder()
        view.frame = NSRect(x: view.frame.origin.x, y: -viewHeight, width: frame.width, height: viewHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.view.animator().setFrameOrigin(NSPoint())
        }
        if mainDataStore.dataChange {
            mainDataStore.dataChange = false
            selectIndex = IndexPath(item: 0, section: 0)
            if !dataList.isEmpty {
                collectionView.scrollToItems(at: [selectIndex], scrollPosition: .left)
            }
        }
        dataList = mainDataStore.dataList
        collectionView.reloadData()
        if !dataList.isEmpty {
            collectionView.selectItems(at: [selectIndex], scrollPosition: .top)
        }
    }
    
    func reLayoutFrame() {
        veView.snp.remakeConstraints { make in
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
    
    public func vcDismiss(completionHandler:(() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.view.animator().setFrameOrigin(NSPoint(x: 0, y: -view.bounds.height))
        }, completionHandler: completionHandler)
    }
    
    
    //MARK: - lazy propty
    lazy var collectionView = {
        let collectionView = NSCollectionView()
        let flowLayout = NSCollectionViewFlowLayout()
        let height = 280;
        flowLayout.itemSize = NSSize(width: height, height: height)
        flowLayout.minimumLineSpacing = 20
        flowLayout.scrollDirection = .horizontal
        flowLayout.headerReferenceSize = NSSize(width: 20, height: height)
        flowLayout.footerReferenceSize = NSSize(width: 20, height: height)
        collectionView.frame = self.view.bounds
        collectionView.wantsLayer = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColors = [.clear]
        collectionView.collectionViewLayout = flowLayout
        collectionView.isSelectable = true
        collectionView.register(NSNib(nibNamed: "PasteCollectionViewItem", bundle: Bundle.main), forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "PasteCollectionViewItem"))
        return collectionView
    }()
    
    lazy var scrollView = {
        let scrollView = PasteScrollView()
        let clipView = NSClipView(frame: self.view.bounds)
        clipView.documentView = collectionView
        scrollView.contentView = clipView
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.autoresizingMask = [.width, .height]
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: -100, right: 0)
        scrollView.delegate = self
        return scrollView
    }()
    
    lazy var veView = {
        let vibrant = NSVisualEffectView(frame: self.view.bounds)
        vibrant.blendingMode = .behindWindow
        return vibrant
    }()
    
}

extension PasteMainViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        if let indexPath = indexPaths.first {
            selectIndex = indexPath
        }
        print("选中\(indexPaths.description)")
        return indexPaths
    }
}

extension PasteMainViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return  dataList.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "PasteCollectionViewItem"), for: indexPath)
        guard let cItem = item as? PasteCollectionViewItem else { return item }
        cItem.delegate = self
        let model = dataList[indexPath.item]
        cItem.updateItem(model:model, index: indexPath)
        return cItem
    }
    
}

extension PasteMainViewController:NSSearchFieldDelegate {
    
    func controlTextDidChange(_ obj: Notification) {
        guard let textView = obj.object as? NSSearchField else { return }
        let keyWord = textView.stringValue
        if !keyWord.isEmpty {
            scrollView.isSearching = true
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            perform(#selector(searchWord), with: self, afterDelay: 0.3)
        } else {
            scrollView.isSearching = false
            dataList = mainDataStore.dataList
            collectionView.reloadData()
        }
    }
    
    @objc func searchWord() {
        let keyWord = searchBar.stringValue
        selectIndex = IndexPath(item: 0, section: 0)
        dataList = mainDataStore.searchData(keyWord)
        collectionView.reloadData()
    }

}

extension PasteMainViewController: PasteScrollViewDelegate {
    
    func loadMoreData() {
        if dataList.count == mainDataStore.totoalCount {
            scrollView.noMore = true
            scrollView.isLoding = false
            return
        }
        dataList = mainDataStore.loadMoreData()
        collectionView.reloadData()
        scrollView.isLoding = false
    }
}

extension PasteMainViewController: PasteCollectionViewItemDelegate {
    
    func deleteItem(_ item: PasteboardModel, indePath: IndexPath) {
        mainDataStore.deleteItem(item: item)
        dataList = mainDataStore.dataList
        collectionView.deleteItems(at: [indePath])
        collectionView.reloadData()
    }
    
}

