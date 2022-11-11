//
//  main.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Cocoa
import Foundation

autoreleasepool { () -> Void in
  let mc = NSApplication.shared
  let mcDelegate = PasteAppDelegate()
  mc.delegate = mcDelegate
  mc.run()
}
