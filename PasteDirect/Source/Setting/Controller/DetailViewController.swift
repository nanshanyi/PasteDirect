import Cocoa
import SnapKit

class DetailViewController: NSViewController {

    private lazy var containerView: NSView = NSView()
    private var currentViewController: NSViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        setupContainerView()
    }

    private func setupContainerView() {
        view.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func showDetail(for item: PreferenceItem) {
        view.window?.title = item.title
        // 移除当前视图控制器
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()

        // 创建新的视图控制器
        let newVC = item.vc

        // 添加新的视图控制器
        addChild(newVC)
        containerView.addSubview(newVC.view)
        newVC.view.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        currentViewController = newVC
    }

}

// MARK: - Empty View Controller
class EmptyViewController: NSViewController {
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
}
