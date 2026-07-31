//
//  Data+ContentHash.swift
//  Paste
//
//  Created by 南山忆 on 2026/07/31.
//

import CryptoKit
import Foundation

extension Data {
    /// 基于内容的稳定哈希(63 位),跨进程/跨重启一致。
    ///
    /// 与 Swift 标准库 `hashValue`(进程级随机播种)不同,相同内容在任何进程都算出相同值,
    /// 因此可作为 SQLite 去重主键、外置图片文件名等持久化标识。
    /// 取 SHA-256 摘要前 8 字节并显式按大端序解释,结果只依赖摘要字节本身,与宿主字节序无关;
    /// 再清零最高位保证非负。63 位有效位下,10 万条记录的碰撞概率约 5e-10,对剪贴板历史量级足够。
    var contentHash: Int {
        let digest = SHA256.hash(data: self)
        let raw = digest.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return Int(UInt64(bigEndian: raw) & 0x7FFF_FFFF_FFFF_FFFF)
    }
}
