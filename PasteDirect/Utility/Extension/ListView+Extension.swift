//
//  NSCollectionView+Extension.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/8.
//

import Cocoa

extension NSCollectionView {
    func register<T: NSCollectionViewItem>(_: T.Type) where T: UserInterfaceItemIdentifier {
        if let nib = T.nib {
            register(nib, forItemWithIdentifier: T.identifier)
        }
        register(T.self, forItemWithIdentifier: T.identifier)
    }
}

extension NSTableView  {
    func register<T: NSTableCellView>(_: T.Type) where T: UserInterfaceItemIdentifier {
        if let nib = T.nib {
            register(nib, forIdentifier: T.identifier)
        }
    }
}
