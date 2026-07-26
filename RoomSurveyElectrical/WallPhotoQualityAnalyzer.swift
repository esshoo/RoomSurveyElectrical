import CoreGraphics
import Foundation
import UIKit

struct WallPhotoImageMetrics: Equatable {
    let averageRed: Float
    let averageGreen: Float
    let averageBlue: Float
    let averageLuminance: Float
    let luminanceContrast: Float
    let edgeDetail: Float
    let shadowClipping: Float
    let highlightClipping: Float
    let qualityScore: Float
}

enum WallPhotoQualityAnalyzer {
    static let weakCaptureThreshold: Float = 0.60

    static func combinedCaptureScore(
        geometricScore: Float,
        jpegData: Data
    ) -> Float {
        guard let image = UIImage(data: jpegData),
              let metrics = analyze(image: image) else {
            return min(max(geometricScore, 0), 1)
        }
        let geometric = min(max(geometricScore, 0), 1)
        return min(
            max(geometric * 0.66 + metrics.qualityScore * 0.34, 0),
            1
        )
    }

    static func analyze(image: UIImage) -> WallPhotoImageMetrics? {
        let sampleSide = 48
        let bytesPerPixel = 4
        let bytesPerRow = sampleSide * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleSide * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleSide,
                height: sampleSide,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            UIGraphicsPopContext()
            return true
        }
        guard rendered else { return nil }

        let pixelCount = sampleSide * sampleSide
        guard pixelCount > 0 else { return nil }

        var sumR: Double = 0
        var sumG: Double = 0
        var sumB: Double = 0
        var sumLuminance: Double = 0
        var sumLuminanceSquared: Double = 0
        var shadowCount = 0
        var highlightCount = 0
        var edgeSum: Double = 0
        var edgeSamples = 0
        var previousRow = [Double](repeating: 0, count: sampleSide)

        for y in 0..<sampleSide {
            var previousLuminance: Double?
            for x in 0..<sampleSide {
                let index = y * bytesPerRow + x * bytesPerPixel
                let red = Double(pixels[index]) / 255
                let green = Double(pixels[index + 1]) / 255
                let blue = Double(pixels[index + 2]) / 255
                let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722

                sumR += red
                sumG += green
                sumB += blue
                sumLuminance += luminance
                sumLuminanceSquared += luminance * luminance
                if luminance < 0.045 { shadowCount += 1 }
                if luminance > 0.955 { highlightCount += 1 }

                if let previousLuminance {
                    edgeSum += abs(luminance - previousLuminance)
                    edgeSamples += 1
                }
                if y > 0 {
                    edgeSum += abs(luminance - previousRow[x])
                    edgeSamples += 1
                }
                previousLuminance = luminance
                previousRow[x] = luminance
            }
        }

        let count = Double(pixelCount)
        let averageLuminance = sumLuminance / count
        let variance = max(sumLuminanceSquared / count - averageLuminance * averageLuminance, 0)
        let contrast = sqrt(variance)
        let detail = edgeSamples > 0 ? edgeSum / Double(edgeSamples) : 0
        let shadowClipping = Double(shadowCount) / count
        let highlightClipping = Double(highlightCount) / count

        let exposureScore: Double
        if averageLuminance < 0.14 {
            exposureScore = max(averageLuminance / 0.14, 0)
        } else if averageLuminance > 0.90 {
            exposureScore = max((1 - averageLuminance) / 0.10, 0)
        } else {
            exposureScore = 1
        }
        let clippingScore = max(1 - (shadowClipping + highlightClipping) * 2.4, 0)
        let contrastScore = min(max(contrast / 0.085, 0.35), 1)
        let detailScore = min(max(detail / 0.032, 0.30), 1)
        let quality = min(
            max(
                exposureScore * 0.42
                    + clippingScore * 0.28
                    + contrastScore * 0.18
                    + detailScore * 0.12,
                0
            ),
            1
        )

        return WallPhotoImageMetrics(
            averageRed: Float(sumR / count),
            averageGreen: Float(sumG / count),
            averageBlue: Float(sumB / count),
            averageLuminance: Float(averageLuminance),
            luminanceContrast: Float(contrast),
            edgeDetail: Float(detail),
            shadowClipping: Float(shadowClipping),
            highlightClipping: Float(highlightClipping),
            qualityScore: Float(quality)
        )
    }
}

extension WallPhotoSegment {
    var isWeakPhotoCapture: Bool {
        guard state == .captured, photoID != nil else { return false }
        if needsRecapture { return true }
        guard let qualityScore else { return false }
        return qualityScore < WallPhotoQualityAnalyzer.weakCaptureThreshold
    }

    var isPhotoCaptureSatisfied: Bool {
        state == .captured && photoID != nil && !needsRecapture
    }
}

struct WallPhotoQualitySummary: Equatable {
    let totalCount: Int
    let goodCount: Int
    let weakCount: Int
    let missingCount: Int

    init(segments: [WallPhotoSegment]) {
        totalCount = segments.count
        weakCount = segments.filter(\.isWeakPhotoCapture).count
        missingCount = segments.filter {
            $0.state != .captured || $0.photoID == nil
        }.count
        goodCount = max(totalCount - weakCount - missingCount, 0)
    }

    var capturedCount: Int { goodCount + weakCount }

    var coverage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(capturedCount) / Double(totalCount)
    }

    var qualityCompletion: Double {
        guard totalCount > 0 else { return 0 }
        return Double(goodCount) / Double(totalCount)
    }

    var isReadyForBestExport: Bool {
        totalCount > 0 && weakCount == 0 && missingCount == 0
    }
}
