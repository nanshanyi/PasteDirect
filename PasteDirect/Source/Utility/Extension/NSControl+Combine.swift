//
//  NSControl+Combine.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/30.
//

import Cocoa
import Combine
import ObjectiveC

private nonisolated(unsafe) var tapSubjectKey: UInt8 = 0

extension NSControl {
    @MainActor
    var tapPublisher: AnyPublisher<Void, Never> {
        if let existing = objc_getAssociatedObject(self, &tapSubjectKey) as? ControlTapHelper {
            return existing.subject.eraseToAnyPublisher()
        }
        let helper = ControlTapHelper()
        objc_setAssociatedObject(self, &tapSubjectKey, helper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        target = helper
        action = #selector(ControlTapHelper.handleAction(_:))
        return helper.subject.eraseToAnyPublisher()
    }
}

private final class ControlTapHelper: NSObject {
    let subject = PassthroughSubject<Void, Never>()

    @objc func handleAction(_ sender: Any) {
        subject.send(())
    }
}
