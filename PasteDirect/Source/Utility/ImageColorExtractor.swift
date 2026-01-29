import Cocoa
import CoreImage
import Accelerate
import simd

struct ImageColorExtractor {
    
    struct DominantColor {
        let dominantColor: NSColor?
        let secondary: NSColor?
        
        var color: NSColor? {
            return secondary ?? dominantColor
        }
    }
        
    private static func _extractDominantColors(from image: NSImage) -> [NSColor] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        
        let resizedImage = resizeImageForProcessing(cgImage)
        let pixelData = extractPixelData(from: resizedImage)
        
        return performKMeansClustering(pixels: pixelData, clusterCount: 2)
    }
    
    static func extractDominantColors(from image: NSImage) async -> DominantColor {
        let colors = _extractDominantColors(from: image)
        return  DominantColor(dominantColor: colors.first, secondary: colors.count > 1 ? colors[1] : nil)
    }
    
    static func extractAverageColor(from image: NSImage) async -> NSColor {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSColor.black
        }
        
        let resizedImage = resizeImageForProcessing(cgImage)
        let pixelData = extractPixelData(from: resizedImage)
        
        guard !pixelData.isEmpty else { return NSColor.black }
        
        let totalColors = pixelData.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1 }
        let averageColor = totalColors / Float(pixelData.count)
                
        return NSColor(red: CGFloat(averageColor.x),
                       green: CGFloat(averageColor.y),
                       blue: CGFloat(averageColor.z),
                       alpha: 1.0)
    }
    
    private static  func adjustColorBrightness(_ color: SIMD3<Float>) -> SIMD3<Float> {
        let brightness = (color.x * 0.299 + color.y * 0.587 + color.z * 0.114)
        
        let targetBrightness: Float = 0.5
        let threshold: Float = 0.15
        
        if brightness < (targetBrightness - threshold) {
            let factor = min(2.0, (targetBrightness - threshold) / max(brightness, 0.1))
            return simd_clamp(color * factor, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
        } else if brightness > (targetBrightness + threshold) {
            let factor = max(0.3, (targetBrightness + threshold) / brightness)
            return color * factor
        }
        
        return color
    }
    
    static func resizeImageForProcessing(_ cgImage: CGImage) -> CGImage {
        let maxDimension: CGFloat = 100
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let ratio = min(maxDimension / width, maxDimension / height)
        let newWidth = Int(width * ratio)
        let newHeight = Int(height * ratio)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: newWidth,
                                height: newHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: newWidth * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()!
    }
    
    private static func extractPixelData(from cgImage: CGImage) -> [SIMD3<Float>] {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        
        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                let alpha = Float(bytes[offset + 3]) / 255.0
                
                if alpha > 0.1 {
                    pixels.append(SIMD3<Float>(r, g, b))
                }
            }
        }
        
        return pixels
    }
    
    private static func performKMeansClustering(pixels: [SIMD3<Float>], clusterCount: Int) -> [NSColor] {
        guard !pixels.isEmpty else { return [] }
        
        let actualClusterCount = min(clusterCount, pixels.count)
        var centroids = initializeCentroids(from: pixels, count: actualClusterCount)
        var clusters: [[SIMD3<Float>]] = Array(repeating: [], count: actualClusterCount)
        
        for _ in 0..<20 {
            clusters = Array(repeating: [], count: actualClusterCount)
            
            for pixel in pixels {
                var minDistance = Float.greatestFiniteMagnitude
                var closestCentroid = 0
                
                for (index, centroid) in centroids.enumerated() {
                    let diff = pixel - centroid
                    let distance = simd_dot(diff, diff)
                    if distance < minDistance {
                        minDistance = distance
                        closestCentroid = index
                    }
                }
                
                clusters[closestCentroid].append(pixel)
            }
            
            var converged = true
            for (index, cluster) in clusters.enumerated() {
                guard !cluster.isEmpty else { continue }
                
                let newCentroid = cluster.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1 } / Float(cluster.count)
                
                let diff = centroids[index] - newCentroid
                if simd_dot(diff, diff) > 0.0001 {
                    converged = false
                }
                centroids[index] = newCentroid
            }
            
            if converged {
                break
            }
        }
        
        return centroids.enumerated().compactMap { index, centroid in
            guard !clusters[index].isEmpty else { return nil }
            return NSColor(red: CGFloat(centroid.x),
                           green: CGFloat(centroid.y),
                           blue: CGFloat(centroid.z),
                           alpha: 1.0)
        }.sorted { color1, color2 in
            let c1 = SIMD3<Float>(Float(color1.redComponent), Float(color1.greenComponent), Float(color1.blueComponent))
            let c2 = SIMD3<Float>(Float(color2.redComponent), Float(color2.greenComponent), Float(color2.blueComponent))
            
            let cluster1Index = centroids.firstIndex {
                let diff = $0 - c1
                return simd_dot(diff, diff) < 0.0001
            } ?? 0
            let cluster2Index = centroids.firstIndex {
                let diff = $0 - c2
                return simd_dot(diff, diff) < 0.0001
            } ?? 0
            return clusters[cluster1Index].count > clusters[cluster2Index].count
        }
    }
    
    private static func initializeCentroids(from pixels: [SIMD3<Float>], count: Int) -> [SIMD3<Float>] {
        var centroids: [SIMD3<Float>] = []
        centroids.append(pixels.randomElement()!)
        
        for _ in 1..<count {
            var distances: [Float] = []
            
            for pixel in pixels {
                let minDistance = centroids.map {
                    let diff = pixel - $0
                    return simd_dot(diff, diff)
                }.min()!
                distances.append(minDistance)
            }
            
            let totalDistance = distances.reduce(0, +)
            let randomValue = Float.random(in: 0...totalDistance)
            
            var cumulative: Float = 0
            for (index, distance) in distances.enumerated() {
                cumulative += distance
                if cumulative >= randomValue {
                    centroids.append(pixels[index])
                    break
                }
            }
        }
        
        return centroids
    }
}
