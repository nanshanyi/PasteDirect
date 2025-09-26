import Cocoa

// MARK: - Preference Item Model
class PreferenceItem {
    
    enum SettingType {
        case general
        case shortcuts
        case ignore
    }
    
    let title: String
    let icon: NSImage?
    let type: SettingType
    let classType: NSViewController.Type
    lazy var vc: NSViewController = classType.init()
    
    init(title: String, icon: NSImage?, type: SettingType, classType: NSViewController.Type) {
        self.title = title
        self.icon = icon
        self.type = type
        self.classType = classType
    }
    
    static let general = PreferenceItem(
        title: "通用",
        icon: NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil),
        type: .general,
        classType: GeneralSettingViewController.self
    )
    
    static let shortcuts = PreferenceItem(
        title: "快捷键",
        icon: NSImage(systemSymbolName: "command", accessibilityDescription: nil),
        type: .shortcuts,
        classType: PasteShortcutsSettingViewController.self
    )
    
    static let ignore = PreferenceItem(
        title: "忽略列表",
        icon: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil),
        type: .ignore,
        classType: PasteIgnoreListController.self
    )
    
    static let allItems = [general, shortcuts, ignore]
}

// MARK: - Delegate Protocol
protocol SidebarDelegate: AnyObject {
    func didSelectItem(_ item: PreferenceItem)
}

// MARK: - Main Split View Controller
class SettingSplitViewController: NSSplitViewController {

    private lazy var sidebarViewController = SidebarViewController().then {
        $0.delegate = self
    }
    private lazy var detailViewController = DetailViewController()
    private lazy var sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController).then {
        $0.minimumThickness = 200
        $0.maximumThickness = 200
        $0.preferredThicknessFraction = 0.25
        $0.allowsFullHeightLayout = true
        $0.titlebarSeparatorStyle = .automatic
    }
    
    private lazy var detailItem = NSSplitViewItem(contentListWithViewController: detailViewController)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewControllers()
    }

    private func setupViewControllers() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        resetState()
    }
}

extension SettingSplitViewController {
    func resetState() {
        sidebarViewController.selectFirstItem()
    }
}

extension SettingSplitViewController: SidebarDelegate {
    func didSelectItem(_ item: PreferenceItem) {
        detailViewController.showDetail(for: item)
    }
}
