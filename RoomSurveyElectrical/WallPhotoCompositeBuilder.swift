import Foundation
import UIKit

enum WallPhotoCompositeBuilder {
    static func rebuildComposite(
        project: inout RoomProject,
        wallID: UUID
    ) throws {
        guard let wall = project.walls.first(where: { $0.id == wallID }) else {
            return
        }
        let capturedSegments = project.photographicSegments(for: wallID)
            .filter { $0.state == .captured && $0.photoID != nil }
        guard !capturedSegments.isEmpty else { return }

        let targetSize = canvasSize(for: wall)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let composite = renderer.image { context in
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            for segment in capturedSegments {
                guard let photoID = segment.photoID,
                      let asset = project.wallPhotos?.first(where: { $0.id == photoID }),
                      let image = WallPhotoStorage.image(projectID: project.id, asset: asset) else {
                    continue
                }
                image.draw(in: destinationRect(
                    for: segment,
                    wall: wall,
                    canvasSize: targetSize
                ))
            }
        }

        guard let fullData = composite.jpegData(compressionQuality: 0.92) else {
            throw WallPhotoStorageError.imageEncodingFailed
        }
        let thumbnail = resized(composite, maximumPixelDimension: 960)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.84) else {
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
        photos.removeAll { $0.id == assetID || ($0.wallID == wallID && $0.fileName == fileName) }
        photos.append(asset)
        project.wallPhotos = photos
        project.normalizeWallPhotoMetadata()

        if let appearanceIndex = project.wallAppearances?.firstIndex(where: {
            $0.wallID == wallID
        }) {
            project.wallAppearances?[appearanceIndex].primaryPhotoID = asset.id
            project.wallAppearances?[appearanceIndex].visualMode = .capturedPhotos
        }
    }

    static func isComposite(_ asset: WallPhotoAsset) -> Bool {
        asset.fileName.hasPrefix("wall-composite-")
    }

    private static func compositeFileName(for wallID: UUID) -> String {
        "wall-composite-\(wallID.uuidString).jpg"
    }

    private static func compositeThumbnailFileName(for wallID: UUID) -> String {
        "wall-composite-\(wallID.uuidString)-thumb.jpg"
    }

    private static func canvasSize(for wall: WallSnapshot) -> CGSize {
        let aspect = CGFloat(max(wall.width, 0.10) / max(wall.height, 0.10))
        let maximumDimension: CGFloat = 2048
        let minimumDimension: CGFloat = 768
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
        let normalizedMinX = CGFloat((segment.localMinX + wall.width / 2) / max(wall.width, 0.001))
        let normalizedMaxX = CGFloat((segment.localMaxX + wall.width / 2) / max(wall.width, 0.001))
        let normalizedTop = CGFloat((wall.height / 2 - segment.localMaxY) / max(wall.height, 0.001))
        let normalizedBottom = CGFloat((wall.height / 2 - segment.localMinY) / max(wall.height, 0.001))
        return CGRect(
            x: normalizedMinX * canvasSize.width,
            y: normalizedTop * canvasSize.height,
            width: max((normalizedMaxX - normalizedMinX) * canvasSize.width, 1),
            height: max((normalizedBottom - normalizedTop) * canvasSize.height, 1)
        ).insetBy(dx: -1, dy: -1)
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
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
