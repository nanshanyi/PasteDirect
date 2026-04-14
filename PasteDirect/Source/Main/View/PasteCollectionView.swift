//
//  PasteCollectionView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/4/11.
//

import Carbon
import Cocoa

protocol PasteCollectionViewKeyDelegate: AnyObject {
    func collectionViewDidPressDelete()
    func collectionViewDidPressReturn()
    func collectionViewDidPressSpace()
    func collectionViewDidPressEscape()
}

final class PasteCollectionView: NSCollectionView {
    weak var keyDelegate: PasteCollectionViewKeyDelegate?

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Delete:
            keyDelegate?.collectionViewDidPressDelete()
        case kVK_Return:
            keyDelegate?.collectionViewDidPressReturn()
        case kVK_Space:
            keyDelegate?.collectionViewDidPressSpace()
        case kVK_Escape:
            keyDelegate?.collectionViewDidPressEscape()
        default:
            super.keyDown(with: event)
        }
    }
}
