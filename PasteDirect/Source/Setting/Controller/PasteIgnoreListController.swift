//
//  PasteIgnoreListController.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/8.
//

import Cocoa
import Settings
import RxCocoa
import RxSwift
import ServiceManagement

enum PasteIgnoreType {
    case `default`
    case custom
}

final class PasteIgnoreListController: NSViewController {
    
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var addTextField: NSTextField!
    
    override var nibName: NSNib.Name? { "PasteIgnoreListController" }
    private let disposeBag = DisposeBag()
    private var customList = BehaviorRelay<[String]>(value: [])
    private lazy var defatulDataList = WindowInfo.defaultList.map { PasteIgnoreListItem(id: $0, type: .default) }
    private var dataList = [PasteIgnoreListItem]()

    override func viewDidLoad() {
        super.viewDidLoad()
        initSubViews()
        initRx()
    }

    private func initSubViews() {
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
    }

    private func initRx() {
        customList.skip(1)
            .bind(onNext: refreshData(_:))
            .disposed(by: disposeBag)
        
        addTextField.rx.text
            .orEmpty.subscribe(
                with: self,
                onNext: { wrapper, text in
                    wrapper.addButton.isEnabled = !text.isEmpty
                })
            .disposed(by: disposeBag)
        
        addButton.rx.tap
            .subscribe(with: self,
                       onNext: { wrapper, _ in
                let text = wrapper.addTextField.stringValue
                var customList = wrapper.customList.value
                guard !text.isEmpty, !customList.contains(text) else { return }
                customList.append(wrapper.addTextField.stringValue)
                wrapper.customList.accept(customList)
                WindowInfo.customList = customList
            })
            .disposed(by: disposeBag)
        customList.accept(WindowInfo.customList)
    }

    private func refreshData(_ customList: [String]) {
        let customList = customList.map { PasteIgnoreListItem(id: $0, type: .custom) }
        dataList = defatulDataList + customList
        tableView.reloadData()
    }
}

extension PasteIgnoreListController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataList.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: PasteIgnoreListCellView.identifier, owner: self) as? PasteIgnoreListCellView ?? PasteIgnoreListCellView()
        cell.delegate = self
        let item = dataList[row]
        cell.updateData(item)
        return cell
    }
}

extension PasteIgnoreListController: PasteIgnoreListCellViewDelegate {
    func deleteItem(_ item: PasteIgnoreListItem) {
        var list = customList.value
        list.removeAll { $0 == item.id }
        customList.accept(list)
        WindowInfo.customList = list
    }
}

struct PasteIgnoreListItem {
    let id: String
    let type: PasteIgnoreType
}
