//
//  ImageThumbnail.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/06/04.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 图片缩略图生成(本地，无网络)。
/// 列表只需要小缩略图，原图外置到文件后，DB 里存这份缩略图即可，避免每页查询背着几 MB 原图。
enum ImageThumbnail {
    /// 缩略图最长边上限。列表项最大也就几百 pt，512px 在 Retina 下足够清晰。
    private static let maxDimension = 512

    /// 解析原图 Data，返回 (缩略图 PNG data, 原图像素尺寸)。
    /// 解码阶段降采样，比先构造全尺寸 NSImage 再缩放更省内存。失败返回 nil。
    static func make(from data: Data) -> (thumbnail: Data, pixelSize: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        // 原图像素尺寸(从元数据读，不解码全图)
        let pixelSize = pixelSize(of: source)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard let pngData = encodePNG(cgThumb) else { return nil }
        return (pngData, pixelSize)
    }

    /// 仅读取原图像素尺寸，不生成缩略图(迁移时回填尺寸用)。
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let size = pixelSize(of: source)
        return size == .zero ? nil : size
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return .zero
        }
        return CGSize(width: w, height: h)
    }

    private static func encodePNG(_ cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
