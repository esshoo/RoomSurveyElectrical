import Foundation
import ImageIO
import UIKit

enum WallPhotoStorageError: LocalizedError {
    case invalidImage
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "ملف الصورة غير صالح أو غير مدعوم."
        case .imageEncodingFailed:
            "تعذر تجهيز صورة الحائط للحفظ."
        }
    }
}

enum WallPhotoStorage {
    static func importImage(
        data: Data,
        projectID: UUID,
        wallID: UUID,
        source: WallPhotoSource = .manualImport
    ) throws -> WallPhotoAsset {
        guard let sourceImage = downsampledImage(
            data: data,
            maximumPixelDimension: 4096
        ) else {
            throw WallPhotoStorageError.invalidImage
        }

        let fullImage = preparedImage(sourceImage, maximumPixelDimension: 4096)
        let thumbnail = preparedImage(fullImage, maximumPixelDimension: 960)
        guard let fullData = fullImage.jpegData(compressionQuality: 0.90),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.82) else {
            throw WallPhotoStorageError.imageEncodingFailed
        }

        let id = UUID()
        let fileName = "wall-photo-\(id.uuidString).jpg"
        let thumbnailFileName = "wall-photo-\(id.uuidString)-thumb.jpg"
        let fullURL = try ProjectRepository.assetURL(
            projectID: projectID,
            fileName: fileName,
            createProjectDirectory: true
        )
        let thumbnailURL = try ProjectRepository.assetURL(
            projectID: projectID,
            fileName: thumbnailFileName,
            createProjectDirectory: true
        )

        do {
            try fullData.write(to: fullURL, options: .atomic)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: fullURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            throw error
        }

        let dimensions = fullImage.pixelDimensions
        return WallPhotoAsset(
            id: id,
            wallID: wallID,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height,
            source: source
        )
    }

    static func image(
        projectID: UUID,
        asset: WallPhotoAsset,
        thumbnail: Bool = false
    ) -> UIImage? {
        let preferredName = thumbnail ? asset.thumbnailFileName : asset.fileName
        let fallbackName = asset.fileName
        for fileName in [preferredName, fallbackName].compactMap({ $0 }) {
            guard let url = try? ProjectRepository.fileURL(
                projectID: projectID,
                fileName: fileName
            ), let image = UIImage(contentsOfFile: url.path) else {
                continue
            }
            return image
        }
        return nil
    }

    static func fileURL(
        projectID: UUID,
        asset: WallPhotoAsset
    ) -> URL? {
        try? ProjectRepository.fileURL(
            projectID: projectID,
            fileName: asset.fileName
        )
    }

    static func delete(
        projectID: UUID,
        asset: WallPhotoAsset
    ) {
        ProjectRepository.removeAsset(
            projectID: projectID,
            fileName: asset.fileName
        )
        ProjectRepository.removeAsset(
            projectID: projectID,
            fileName: asset.thumbnailFileName
        )
    }

    private static func downsampledImage(
        data: Data,
        maximumPixelDimension: CGFloat
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func preparedImage(
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
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension UIImage {
    var pixelDimensions: (width: Int, height: Int) {
        if let cgImage {
            return (cgImage.width, cgImage.height)
        }
        return (
            max(Int((size.width * scale).rounded()), 1),
            max(Int((size.height * scale).rounded()), 1)
        )
    }
}
