//
//  Log.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/26.
//

import Foundation

public func Log(_ info: String, file: String = #file, function: String = #function, line: UInt = #line) {
#if DEBUG
    print("【\(file.components(separatedBy: "/").last ?? "")】func-\(function)line-\(line): \(info)")
#endif
}


