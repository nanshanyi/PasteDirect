//
//  View+Extension.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/28.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func apply<V: View>(@ViewBuilder transform: (Self) -> V) -> some View {
        transform(self)
    }
}
