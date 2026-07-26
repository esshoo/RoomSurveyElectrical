import CoreImage
import Foundation
import UIKit

struct WallPhotoCompositeResult: Equatable {
    let capturedCount: Int
    let weakCount: Int
    let missingCount: Int
}

enum WallPhotoCompositeBuilder {
    private static let ciContext = CIContext(options: [
        .cacheIntermediates: false
    ])

    @discardableResult
    static func rebuildComposite(
        project: inout RoomProject,
        wallID: UUID,
        performanceProfile: SpatialScanPerformanceProfile = .balanced
    ) throws -> WallPhotoCompositeResult {
        guard let wall = project.walls.first(where: { $0.id == wallID }) else {
            return WallPhotoCompositeResult(capturedCount: 0, weakCount: 0, missingCount: 0)
        }
        let wallSegments = project.photographicSegments(for: wallID)
        let summary = WallPhotoQualitySummary(segments: wallSegments)
        let capturedSegments = wallSegments.filter {
            $0.state == .captured && $0.photoID != nil
        }
        guard !capturedSegments.isEmpty else {
            return WallPhotoCompositeResult(
                capturedCount: 0,
                weakCount: summary.weakCount,
                missingCount: summary.missingCount
            )
        }

        let targetSize = canvasSize(
            for: wall,
            maximumDimension: CGFloat(
                performanceProfile.photoCompositeMaximumDimension
            )
        )
        let referenceColor = colorReference(
            project: project,
            segments: capturedSegments
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let composite = renderer.image { rendererContext in
            UIColor(white: 0.88, alpha: 1).setFill()
            rendererContext.fill(CGRect(origin: .zero, size: targetSize))

            for segment in capturedSegments {
                autoreleasepool {
                    guard let photoID = segment.photoID,
                          let asset = project.wallPhotos?.first(where: { $0.id == photoID }),
                          let sourceImage = WallPhotoStorage.image(
                            projectID: project.id,
                            asset: asset
                          ) else {
                        return
                    }
                    let rect = destinationRect(
                        for: segment,
                        wall: wall,
                        canvasSize: targetSize
                    )
                    let metrics = WallPhotoQualityAnalyzer.analyze(image: sourceImage)
                    let prepared = preparedImage(
                        sourceImage,
                        metrics: metrics,
                        reference: referenceColor,
                        targetSize: CGSize(
                            width: max(rect.width.rounded(.up), 1),
                            height: max(rect.height.rounded(.up), 1)
                        )
                    )
                    prepared.draw(
                        in: rect.insetBy(dx: -0.75, dy: -0.75),
                        blendMode: .normal,
                        alpha: 1
                    )

                    let overlap = min(max(min(rect.width, rect.height) * 0.055, 5), 18)
                    let blendRect = rect.insetBy(dx: -overlap, dy: -overlap)
                    drawFeatheredOverlay(
                        prepared,
                        in: blendRect,
                        segment: segment,
                        context: rendererContext.cgContext
                    )
                }
            }
        }

        guard let fullData = composite.jpegData(
            compressionQuality: CGFloat(
                performanceProfile.capturedPhotoJPEGQuality
            )
        ) else {
            throw WallPhotoStorageError.imageEncodingFailed
        }
        let thumbnail = resized(
            composite,
            maximumPixelDimension: CGFloat(
                performanceProfile.photoThumbnailMaximumDimension
            )
        )
        guard let thumbnailData = thumbnail.jpegData(
            compressionQuality: max(
                CGFloat(performanceProfile.capturedPhotoJPEGQuality) - 0.08,
                0.72
            )
        ) else {
            throw WallPhotoStorageError.imageEncodingFailed
        }

        let existing = project.wallPhotos?.first(where: {
            $0.wallID == wallID && $0.fileName == compositeFileName(for: wallID)
        })
        let assetID = existing?.id ?? UUID()
        let fileName = compositeFileName(for: wallID)
        let thumbnailFileName = compositeThumbnailFileName(for: wallID)
        let fullURL = try ProjectRepository.assetURL(
            projectID: project.id,
            fileName: fileName,
            createProjectDirectory: true
        )
        let thumbnailURL = try ProjectRepository.assetURL(
            projectID: project.id,
            fileName: thumbnailFileName,
            createProjectDirectory: true
        )
        WallPhotoStorage.removeCachedImage(
            projectID: project.id,
            fileName: fileName
        )
        WallPhotoStorage.removeCachedImage(
            projectID: project.id,
            fileName: thumbnailFileName
        )
        try fullData.write(to: fullURL, options: .atomic)
        try thumbnailData.write(to: thumbnailURL, options: .atomic)

        let asset = WallPhotoAsset(
            id: assetID,
            wallID: wallID,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            createdAt: existing?.createdAt ?? Date(),
            pixelWidth: max(Int(targetSize.width.rounded()), 1),
            pixelHeight: max(Int(targetSize.height.rounded()), 1),
            source: .photographicScan,
            segmentIDs: capturedSegments.map(\.id),
            isEdited: false
        )

        var photos = project.wallPhotos ?? []
        photos.removeAll {
            $0.id == assetID || ($0.wallID == wallID && $0.fileName == fileName)
        }
        photos.append(asset)
        project.wallPhotos = photos
        project.normalizeWallPhotoMetadata()

        if let appearanceIndex = project.wallAppearances?.firstIndex(where: {
            $0.wallID == wallID
        }) {
            project.wallAppearances?[appearanceIndex].primaryPhotoID = asset.id
            project.wallAppearances?[appearanceIndex].visualMode = .capturedPhotos
        }

        return WallPhotoCompositeResult(
            capturedCount: summary.capturedCount,
            weakCount: summary.weakCount,
            missingCount: summary.missingCount
        )
    }

    static func isComposite(_ asset: WallPhotoAsset) -> Bool {
        asset.fileName.hasPrefix("wall-composite-")
    }

    private struct ColorReference {
        let red: Float
        let green: Float
        let blue: Float
    }

    private static func colorReference(
        project: RoomProject,
        segments: [WallPhotoSegment]
    ) -> ColorReference? {
        var red: Double = 0
        var green: Double = 0
        var blue: Double = 0
        var totalWeight: Double = 0

        for segment in segments {
            autoreleasepool {
                guard let photoID = segment.photoID,
                      let asset = project.wallPhotos?.first(where: { $0.id == photoID }),
                      let image = WallPhotoStorage.image(projectID: project.id, asset: asset),
                      let metrics = WallPhotoQualityAnalyzer.analyze(image: image) else {
                    return
                }
                let weight = Double(max(segment.qualityScore ?? 0.72, 0.20))
                red += Double(metrics.averageRed) * weight
                green += Double(metrics.averageGreen) * weight
                blue += Double(metrics.averageBlue) * weight
                totalWeight += weight
            }
        }
        guard totalWeight > 0 else { return nil }
        return ColorReference(
            red: Float(red / totalWeight),
            green: Float(green / totalWeight),
            blue: Float(blue / totalWeight)
        )
    }

    private static func preparedImage(
        _ image: UIImage,
        metrics: WallPhotoImageMetrics?,
        reference: ColorReference?,
        targetSize: CGSize
    ) -> UIImage {
        let resizedImage = resizedExact(image, targetSize: targetSize)
        guard let metrics,
              let reference,
              let input = CIImage(image: resizedImage) else {
            return resizedImage
        }

        let redScale = min(max(reference.red / max(metrics.averageRed, 0.05), 0.82), 1.18)
        let greenScale = min(max(reference.green / max(metrics.averageGreen, 0.05), 0.82), 1.18)
        let blueScale = min(max(reference.blue / max(metrics.averageBlue, 0.05), 0.82), 1.18)

        guard let matrix = CIFilter(name: "CIColorMatrix") else {
            return resizedImage
        }
        matrix.setValue(input, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: CGFloat(redScale), y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: CGFloat(greenScale), z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: CGFloat(blueScale), w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let output = matrix.outputImage,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else {
            return resizedImage
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private static func drawFeatheredOverlay(
        _ image: UIImage,
        in rect: CGRect,
        segment: WallPhotoSegment,
        context: CGContext
    ) {
        guard let mask = featherMask(for: segment) else { return }
        context.saveGState()
        context.clip(to: rect, mask: mask)
        image.draw(in: rect, blendMode: .normal, alpha: 0.34)
        context.restoreGState()
    }

    private static func featherMask(for segment: WallPhotoSegment) -> CGImage? {
        let side = 64
        let feather = 14.0
        let hasLeft = segment.column > 0
        let hasRight = segment.column < segment.columnCount - 1
        let hasBottom = segment.row > 0
        let hasTop = segment.row < segment.rowCount - 1
        var bytes = [UInt8](repeating: 255, count: side * side)

        for y in 0..<side {
            for x in 0..<side {
                var alpha = 1.0
                if hasLeft {
                    alpha = min(alpha, 0.24 + 0.76 * min(Double(x) / feather, 1))
                }
                if hasRight {
                    alpha = min(alpha, 0.24 + 0.76 * min(Double(side - 1 - x) / feather, 1))
                }
                if hasTop {
                    alpha = min(alpha, 0.24 + 0.76 * min(Double(y) / feather, 1))
                }
                if hasBottom {
                    alpha = min(alpha, 0.24 + 0.76 * min(Double(side - 1 - y) / feather, 1))
                }
                bytes[y * side + x] = UInt8(min(max(alpha, 0), 1) * 255)
            }
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func compositeFileName(for wallID: UUID) -> String {
        "wall-composite-\(wallID.uuidString).jpg"
    }

    private static func compositeThumbnailFileName(for wallID: UUID) -> String {
        "wall-composite-\(wallID.uuidString)-thumb.jpg"
    }

    private static func canvasSize(
        for wall: WallSnapshot,
        maximumDimension: CGFloat
    ) -> CGSize {
        let aspect = CGFloat(max(wall.width, 0.10) / max(wall.height, 0.10))
        let maximumDimension = max(maximumDimension, 1024)
        let minimumDimension = min(maximumDimension * 0.375, 960)
        if aspect >= 1 {
            let width = maximumDimension
            let height = max(minimumDimension, width / max(aspect, 0.01))
            return CGSize(width: width, height: min(height, maximumDimension))
        }
        let height = maximumDimension
        let width = max(minimumDimension, height * aspect)
        return CGSize(width: min(width, maximumDimension), height: height)
    }

    private static func destinationRect(
        for segment: WallPhotoSegment,
        wall: WallSnapshot,
        canvasSize: CGSize
    ) -> CGRect {
        let normalizedMinX = CGFloat(
            (segment.localMinX + wall.width / 2) / max(wall.width, 0.001)
        )
        let normalizedMaxX = CGFloat(
            (segment.localMaxX + wall.width / 2) / max(wall.width, 0.001)
        )
        let normalizedTop = CGFloat(
            (wall.height / 2 - segment.localMaxY) / max(wall.height, 0.001)
        )
        let normalizedBottom = CGFloat(
            (wall.height / 2 - segment.localMinY) / max(wall.height, 0.001)
        )
        return CGRect(
            x: normalizedMinX * canvasSize.width,
            y: normalizedTop * canvasSize.height,
            width: max((normalizedMaxX - normalizedMinX) * canvasSize.width, 1),
            height: max((normalizedBottom - normalizedTop) * canvasSize.height, 1)
        )
    }

    private static func resizedExact(
        _ image: UIImage,
        targetSize: CGSize
    ) -> UIImage {
        let safeSize = CGSize(
            width: max(targetSize.width.rounded(.up), 1),
            height: max(targetSize.height.rounded(.up), 1)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: safeSize, format: format).image { context in
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: safeSize))
            image.draw(in: CGRect(origin: .zero, size: safeSize))
        }
    }

    private static func resized(
        _ image: UIImage,
        maximumPixelDimension: CGFloat
    ) -> UIImage {
        let width = max(image.size.width * image.scale, 1)
        let height = max(image.size.height * image.scale, 1)
        let scale = min(1, maximumPixelDimension / max(width, height))
        let targetSize = CGSize(
            width: max(round(width * scale), 1),
            height: max(round(height * scale), 1)
        )
        return resizedExact(image, targetSize: targetSize)
    }
}
