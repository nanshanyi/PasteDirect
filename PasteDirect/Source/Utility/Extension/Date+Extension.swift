//
//  Date+Extension.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/1.
//

import AppKit

extension Date {
    var timeAgo: String {
        let diffDate = NSCalendar.current.dateComponents([.month, .day, .hour, .minute], from: self, to: Date())
        if let month = diffDate.month, month > 0 {
            return String(localized: "\(month) months ago")
        } else if let day = diffDate.day, day > 0 {
            return String(localized: "\(day) days ago")
        } else if let hour = diffDate.hour, hour > 0 {
            return String(localized: "\(hour) hours ago")
        } else if let minute = diffDate.minute, minute > 0 {
            return String(localized: "\(minute) minutes ago")
        } else {
            return String(localized: "Just now")
        }
    }
}

