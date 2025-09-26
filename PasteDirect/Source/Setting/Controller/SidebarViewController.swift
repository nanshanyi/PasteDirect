import Cocoa
import SnapKit

class SidebarViewController: NSViewController {
    private lazy var tableView = NSTableView().then {
        $0.headerView = nil
        $0.backgroundColor = .clear
        $0.selectionHighlightStyle = .regular
        $0.style = .sourceList
        $0.intercellSpacing = NSSize(width: 0, height: 0)
        $0.rowHeight = 32
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PreferenceColumn"))
        $0.addTableColumn(column)
        $0.dataSource = self
        $0.delegate = self
    }
    private lazy var scrollView = NSScrollView().then {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.hasVerticalScroller = false
        $0.hasHorizontalScroller = false
        $0.drawsBackground = false
        $0.documentView = tableView
    }
    
    private let items = PreferenceItem.allItems

    weak var delegate: SidebarDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }

    private func setupTableView() {
        view.wantsLayer = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func selectFirstItem() {
        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            delegate?.didSelectItem(items[0])
        }
    }
}

// MARK: - NSTableViewDataSource
extension SidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}

// MARK: - NSTableViewDelegate
extension SidebarViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        var cell = tableView.makeView(withIdentifier: SettingTableCellView.identifier, owner: self) as? SettingTableCellView
        if cell == nil {
            cell = SettingTableCellView()
        }
        cell?.configcell(item)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < items.count {
            delegate?.didSelectItem(items[selectedRow])
        }
    }
}
