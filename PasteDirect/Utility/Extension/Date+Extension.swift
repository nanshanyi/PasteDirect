//
//  Date+Extension.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/1.
//

import Foundation

extension Date {
    var timeAgo: String {
        let diffDate = NSCalendar.current.dateComponents([.month, .day, .hour, .minute], from: self, to: Date())
        if let month = diffDate.month, month > 0 {
            return "\(month)月前"
        } else if let day = diffDate.day, day > 0 {
            return "\(day)天前"
        } else if let hour = diffDate.hour, hour > 0 {
            return "\(hour)小时前"
        } else if let minute = diffDate.minute, minute > 0 {
            return "\(minute)分钟前"
        } else {
            return "刚刚"
        }
    }
}
