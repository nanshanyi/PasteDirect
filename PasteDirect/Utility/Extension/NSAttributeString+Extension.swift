//
//  NSAttributeString+Extension.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/11.
//

import Foundation

extension NSAttributedString {
    
    convenience init?(with data: Data, type: PasteboardType) {
        switch type {
        case .rtf:
            self.init(rtf: data, documentAttributes: nil)
        case .rtfd:
            self.init(rtfd: data, documentAttributes: nil)
        case .string:
            try? self.init(data: data, options: [:], documentAttributes: nil)
        case .html:
            self.init(html: data, documentAttributes: nil)
        default:
            return nil
        }
    }
}
