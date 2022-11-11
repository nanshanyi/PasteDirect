//
//  HotKey.swift
//  HotKey
//
//  Created by Henry on 2018/09/15.
//  Copyright © 2018 Eonil. All rights reserved.
//

import Carbon
import Foundation
import AppKit

private let signature = FourCharCode(0x0F0F0F0F)

/// The manager object to access to Carbon's hot-key subsystem.
/// Carbon's hot-key subsystem provides system-wide global shortcut-key
/// processing.
public final class HotKey {
    /// Singleton instance.
    /// As hot-key subsystem is system-wide global feature, it has to
    /// be a singleton object.
    public static let shared = try! HotKey()

    /// Delegate to processing user's hot-key input.
    public var delegate: ((Note) -> Void)?

    private var carbonEventHandler: EventHandlerRef?

    private var keyComboIDSeed = UInt32(0)
    private var idTable = [UInt32: (KeyCombo, EventHotKeyRef?)]()

    private init() throws {
        let ssptr = Unmanaged.passUnretained(self).toOpaque()
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed))
        var h: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            redirectCallbackToContext as EventHandlerUPP,
            1,
            &spec,
            ssptr,
            &h)
        guard status == noErr else { throw Issue.systemCallFail(status) }
        guard let h1 = h else { throw Issue.inconsistentSystemCallResult("Call to `InstallEventHandler` failed. Finished with result code `noErr`, but no event handler object returned.") }
        carbonEventHandler = h1
    }
    deinit {
        let ks = Array(idTable.values.map({ k, _ in k }))
        for k in ks {
            do {
                try unwatch(k)
            }
            catch let err {
                Report.fatalError(.unexpectedErrorInDeinit(err))
            }
        }

        let r = RemoveEventHandler(carbonEventHandler)
        guard r == noErr else {
            Report.fatalError(.unexpectedSystemCallFailureInDeinit(r))
            return
        }
    }

    /// Start watching for a key-combo.
    /// If user input the key-combo, the event will be notified to `delgate`.
    public func watch(_ k: KeyCombo) throws {
        guard idTable.values.contains(where: { k1, _ in k1 == k }) == false else { return }
        if keyComboIDSeed == UInt32.max {
            try reissueAllIDs()
        }
        let id = issueNewID()
        let eid = EventHotKeyID(signature: signature, id: id)
        var obj: EventHotKeyRef?
        let r = RegisterEventHotKey(
            UInt32(k.keyCode),
            uint32(k.modifierFlags.toCarbon()),
            eid,
            GetEventDispatcherTarget(),
            OptionBits(0),
            &obj)

        guard r == noErr else {
            throw Issue.systemCallFail(r)
        }
        idTable[id] = (k, obj)
    }
    private func issueNewID() -> UInt32 {
        keyComboIDSeed += 1
        return keyComboIDSeed
    }
    /// Watching for a key combination consumes an ID internally.
    /// If key-space for ID fully consumed, no more key can be created.
    /// This method unregister all key combinations and re-register them
    /// to avoid the consumption issue.
    ///
    /// As this situation is very unlikely to happen,
    /// performance will be optimized for other operations.
    private func reissueAllIDs() throws {
        let ks = Array(idTable.values.map({ k, _ in k }))
        for k in ks {
            try unwatch(k)
        }
        keyComboIDSeed = 0
        for k in ks {
            try watch(k)
        }
    }
    /// Stops watching for a key-combo.
    public func unwatch(_ k: KeyCombo) throws {
        // Once consumed ID won't be re-used.
        for (id, (k1, o)) in idTable {
            guard k1 == k else { continue }
            let r = UnregisterEventHotKey(o)
            guard r == noErr else { throw Issue.systemCallFail(r) }
            idTable[id] = nil
        }
    }

    fileprivate func processCarbonEvent(_ call: EventHandlerCallRef?, _ event: EventRef?) -> OSStatus {
//        guard let call = call else { return OSStatus(eventNotHandledErr) }
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        guard GetEventClass(event) == kEventClassKeyboard else { return OSStatus(eventNotHandledErr) }
        var eid = EventHotKeyID(signature: 0x0, id: 0)
        let eidsz = MemoryLayout.size(ofValue: eid)
        let r = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            eidsz,
            nil,
            &eid)
        guard r == noErr else { return OSStatus(eventNotHandledErr) }
        guard eid.signature == signature else { return OSStatus(eventNotHandledErr) }
        guard let (k, _) = idTable[eid.id] else { return OSStatus(eventNotHandledErr) }
        precondition(Thread.isMainThread)
        delegate?(.keyPress(k))
        return noErr
    }
    
    func postCmdVEvent() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        cgEvent?.flags = .maskCommand
        cgEvent?.post(tap: .cghidEventTap)
    }
}
public extension HotKey {
    enum Issue: Error {
        case systemCallFail(OSStatus)
        case inconsistentSystemCallResult(String)
    }
    /// Notification from hot-key subsystem.
    /// Any key-combo will be notified.
    enum Note {
        /// Key-combo has been pressed by end-user.
        case keyPress(KeyCombo)
//        case keyRelease(HotKey)
    }
}

private func redirectCallbackToContext(_ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer!) -> OSStatus {
    let ss = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
    return ss.processCarbonEvent(call, event)
}

private extension NSEvent.ModifierFlags {
    init(carbon: UInt32) {
        self = [
            carbon & UInt32(cmdKey) != 0 ? .command : [],
            carbon & UInt32(optionKey) != 0 ? .option : [],
            carbon & UInt32(controlKey) != 0 ? .control : [],
            carbon & UInt32(shiftKey) != 0 ? .shift : [],
        ]
    }
    func toCarbon() -> UInt32 {
        let i = (contains(.command) ? cmdKey : 0)
            | (contains(.option) ? optionKey : 0)
            | (contains(.control) ? controlKey : 0)
            | (contains(.shift) ? shiftKey : 0);
        return UInt32(i)
    }
}
