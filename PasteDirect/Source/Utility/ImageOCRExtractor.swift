//
//  ImageOCRExtractor.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/05/30.
//

import AppKit
import ImageIO
import Vision

/// 用 Vision 框架对图片做文字识别(本地,无网络请求)
enum ImageOCRExtractor {
    /// 识别用的最长边上限:解码阶段就降采样到这个尺寸,避免对超大截图做识别过慢。
    /// 对 Vision 文字识别来说 2000px 足够,再大基本只增加耗时不提升准确率。
    private static let maxDimension = 2000

    /// 识别的目标语言:剪贴板场景固定中英,比自动检测更稳定
    private static let recognitionLanguages = ["zh-Hans", "en-US"]

    /// 同步阻塞 Vision 调用,放进 `Task.detached` / 自定义 actor 内部使用。
    /// 直接吃原始图片 `Data`,在解码阶段降采样(比先构造全尺寸 NSImage 再缩放更省内存、更快)。
    static func extractText(from data: Data) -> String? {
        guard let cgImage = downsampledCGImage(from: data) else { return nil }
        return recognizeText(in: cgImage)
    }

    /// 兜底:仅有 NSImage 时使用(无法走解码期降采样,按原始像素识别)
    static func extractText(from image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return recognizeText(in: cgImage)
    }

    // MARK: - Vision 识别核心

    private static func recognizeText(in cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log("OCR perform failed: \(error)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    // MARK: - 解码期降采样

    /// 用 ImageIO 在解码阶段把最长边降到 `maxDimension`;原图已够小则按原尺寸解码。
    /// 这是真正的重采样,返回的 CGImage 像素尺寸确实变小。
    private static func downsampledCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
