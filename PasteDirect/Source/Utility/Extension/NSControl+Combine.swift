//
//  NSControl+Combine.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/30.
//

import Cocoa
import Combine

extension NSControl {
    var tapPublisher: AnyPublisher<Void, Never> {
        return ControlTapPublisher(control: self)
            .eraseToAnyPublisher()
    }
}

private struct ControlTapPublisher: Publisher {
    typealias Output = Void
    typealias Failure = Never

    let control: NSControl

    func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, S.Input == Void {
        let subscription = ControlTapSubscription(subscriber: subscriber, control: control)
        subscriber.receive(subscription: subscription)
    }
}

private final class ControlTapSubscription<S: Subscriber>: Subscription where S.Input == Void, S.Failure == Never {
    private var subscriber: S?
    private weak var control: NSControl?
    private var target: ControlTarget?

    init(subscriber: S, control: NSControl) {
        self.subscriber = subscriber
        self.control = control
        self.target = ControlTarget { [weak self] in
            _ = self?.subscriber?.receive(())
        }
        control.target = target
        control.action = #selector(ControlTarget.action(_:))
    }

    func request(_ demand: Subscribers.Demand) {}

    func cancel() {
        subscriber = nil
        control?.target = nil
        control?.action = nil
        target = nil
    }
}

private final class ControlTarget: NSObject {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func action(_ sender: Any) {
        handler()
    }
}
