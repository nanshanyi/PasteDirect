//
//  NSAttributeString+Extension.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/11.
//

import AppKit

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
            guard let html = NSMutableAttributedString(html: data, documentAttributes: nil) else {
                return nil
            }
            html.enumerateAttribute(.font, in: NSMakeRange(0, html.length)) { attribute, range, stoped in
                if range.location > maxLength {
                    stoped.pointee = true
                }
                if let font = attribute as? NSFont {
                    html.addAttribute(.font, value: NSFont.systemFont(ofSize: font.pointSize), range: range)
                }
            }
            self.init(attributedString: html)
        default:
            return nil
        }
    }
}
