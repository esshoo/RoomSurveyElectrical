import CoreText
import Foundation
import simd
import UIKit

enum LayeredPlanPDFBuilder {
    private static let pageWidth = 1190.55
    private static let pageHeight = 841.89

    private struct LayerDefinition {
        let name: String
        let stroke: RGBColor
        let fill: RGBColor?
    }

    private static let layers: [LayerDefinition] = [
        LayerDefinition(
            name: "FLOOR",
            stroke: RGBColor(0.65, 0.67, 0.70),
            fill: RGBColor(0.88, 0.89, 0.91)
        ),
        LayerDefinition(
            name: "WALLS",
            stroke: RGBColor(0.07, 0.38, 0.64),
            fill: nil
        ),
        LayerDefinition(
            name: "DOORS",
            stroke: RGBColor(1.00, 0.48, 0.10),
            fill: nil
        ),
        LayerDefinition(
            name: "WINDOWS",
            stroke: RGBColor(0.18, 0.68, 0.88),
            fill: nil
        ),
        LayerDefinition(
            name: "OPENINGS",
            stroke: RGBColor(0.62, 0.28, 0.78),
            fill: nil
        ),
        LayerDefinition(
            name: "FURNITURE",
            stroke: RGBColor(0.47, 0.49, 0.52),
            fill: RGBColor(0.83, 0.84, 0.86)
        ),
        LayerDefinition(
            name: "ELECTRICAL_EXISTING",
            stroke: RGBColor(0.18, 0.72, 0.30),
            fill: RGBColor(0.18, 0.72, 0.30)
        ),
        LayerDefinition(
            name: "ELECTRICAL_PROPOSED",
            stroke: RGBColor(1.00, 0.55, 0.08),
            fill: RGBColor(1.00, 0.55, 0.08)
        ),
        LayerDefinition(
            name: "CEILING_LIGHTING",
            stroke: RGBColor(0.95, 0.58, 0.05),
            fill: RGBColor(1.00, 0.82, 0.10)
        ),
        LayerDefinition(
            name: "DIM_WALLS",
            stroke: RGBColor(0.07, 0.38, 0.64),
            fill: RGBColor(0.07, 0.38, 0.64)
        ),
        LayerDefinition(
            name: "DIM_ELECTRICAL",
            stroke: RGBColor(0.36, 0.20, 0.74),
            fill: RGBColor(0.36, 0.20, 0.74)
        ),
        LayerDefinition(
            name: "ANNOTATIONS",
            stroke: RGBColor(0.12, 0.12, 0.14),
            fill: RGBColor(0.12, 0.12, 0.14)
        )
    ]

    static func build(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) throws -> Data {
        guard !rooms.isEmpty else {
            throw ProjectExportError.noRooms
        }

        let layerObjectStart = 3
        let layerObjectIDs = layers.indices.map {
            layerObjectStart + $0
        }
        let firstPageObjectID = layerObjectStart
            + layerObjectIDs.count
        let pageObjectIDs = rooms.indices.map {
            firstPageObjectID + $0 * 2
        }
        let contentObjectIDs = pageObjectIDs.map { $0 + 1 }
        let infoObjectID = firstPageObjectID + rooms.count * 2
        let objectCount = infoObjectID
        var objects = Array<Data?>(
            repeating: nil,
            count: objectCount + 1
        )

        let layerReferences = layerObjectIDs.map {
            "\($0) 0 R"
        }.joined(separator: " ")
        objects[1] = Data(
            """
            << /Type /Catalog
               /Pages 2 0 R
               /PageMode /UseOC
               /OCProperties <<
                   /OCGs [\(layerReferences)]
                   /D <<
                       /Name (3ERoomElectrical CAD Layers)
                       /BaseState /ON
                       /ON [\(layerReferences)]
                       /OFF []
                       /Order [\(layerReferences)]
                       /Locked []
                       /RBGroups []
                       /AS [
                           << /Event /View
                              /Category [/View]
                              /OCGs [\(layerReferences)]
                           >>
                           << /Event /Print
                              /Category [/Print]
                              /OCGs [\(layerReferences)]
                           >>
                           << /Event /Export
                              /Category [/Export]
                              /OCGs [\(layerReferences)]
                           >>
                       ]
                   >>
               >>
            >>
            """.utf8
        )
        let pageReferences = pageObjectIDs.map {
            "\($0) 0 R"
        }.joined(separator: " ")
        objects[2] = Data(
            """
            << /Type /Pages
               /Kids [\(pageReferences)]
               /Count \(rooms.count)
            >>
            """.utf8
        )

        for (index, layer) in layers.enumerated() {
            objects[layerObjectIDs[index]] = Data(
                """
                << /Type /OCG
                   /Name (\(pdfEscaped(layer.name)))
                   /Intent [/View /Design]
                   /Usage <<
                       /View << /ViewState /ON >>
                       /Print << /PrintState /ON >>
                       /Export << /ExportState /ON >>
                   >>
                >>
                """.utf8
            )
        }

        for (index, room) in rooms.enumerated() {
            let pageID = pageObjectIDs[index]
            let contentID = contentObjectIDs[index]
            let propertyEntries = layerObjectIDs.enumerated().map {
                "/L\($0.offset + 1) \($0.element) 0 R"
            }.joined(separator: " ")
            let content = LayeredPlanPage(
                title: rooms.count == 1 ? title : room.scan.name,
                record: room,
                metadata: metadata
            ).content()
            objects[contentID] = streamObject(content)
            objects[pageID] = Data(
                """
                << /Type /Page
                   /Parent 2 0 R
                   /MediaBox [0 0 \(pdfNumber(pageWidth)) \(pdfNumber(pageHeight))]
                   /Resources <<
                       /ProcSet [/PDF]
                       /Properties << \(propertyEntries) >>
                   >>
                   /Contents \(contentID) 0 R
                >>
                """.utf8
            )
        }

        objects[infoObjectID] = Data(
            """
            << /Title (3ERoomElectrical Layered 2D Plan)
               /Author (3Essam)
               /Creator (3ERoomElectrical)
               /Producer (3ERoomElectrical Layered PDF Engine)
               /CreationDate (D:\(pdfDate(metadata.exportedAt)))
            >>
            """.utf8
        )

        return makePDF(
            objects: objects,
            rootObjectID: 1,
            infoObjectID: infoObjectID
        )
    }

    private static func streamObject(_ content: Data) -> Data {
        var data = Data(
            "<< /Length \(content.count) >>\nstream\n".utf8
        )
        data.append(content)
        data.append(Data("\nendstream".utf8))
        return data
    }

    private static func makePDF(
        objects: [Data?],
        rootObjectID: Int,
        infoObjectID: Int
    ) -> Data {
        var result = Data("%PDF-1.7\n%".utf8)
        result.append(contentsOf: [0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets = Array(
            repeating: 0,
            count: objects.count
        )

        for objectID in 1..<objects.count {
            guard let object = objects[objectID] else { continue }
            offsets[objectID] = result.count
            result.append(
                Data("\(objectID) 0 obj\n".utf8)
            )
            result.append(object)
            result.append(Data("\nendobj\n".utf8))
        }

        let crossReferenceOffset = result.count
        result.append(
            Data("xref\n0 \(objects.count)\n".utf8)
        )
        result.append(Data("0000000000 65535 f \n".utf8))
        for objectID in 1..<objects.count {
            result.append(
                Data(
                    String(
                        format: "%010d 00000 n \n",
                        offsets[objectID]
                    ).utf8
                )
            )
        }
        result.append(
            Data(
                """
                trailer
                << /Size \(objects.count)
                   /Root \(rootObjectID) 0 R
                   /Info \(infoObjectID) 0 R
                >>
                startxref
                \(crossReferenceOffset)
                %%EOF
                """.utf8
            )
        )
        return result
    }
}

private struct LayeredPlanPage {
    let title: String
    let record: ExportRoomRecord
    let metadata: ExportDocumentMetadata

    private let pageWidth: CGFloat = 1190.55
    private let pageHeight: CGFloat = 841.89

    func content() -> Data {
        guard let projection = PDFPlanProjection(
            project: record.project,
            pageWidth: pageWidth,
            pageHeight: pageHeight
        ) else {
            return Data()
        }
        var commands = PDFLayerCommands(
            layerNames: [
                "FLOOR",
                "WALLS",
                "DOORS",
                "WINDOWS",
                "OPENINGS",
                "FURNITURE",
                "ELECTRICAL_EXISTING",
                "ELECTRICAL_PROPOSED",
                "CEILING_LIGHTING",
                "DIM_WALLS",
                "DIM_ELECTRICAL",
                "ANNOTATIONS"
            ]
        )

        commands.base(
            "q 1 1 1 rg 0 0 \(pdfNumber(pageWidth)) \(pdfNumber(pageHeight)) re f Q\n"
        )
        addFloors(
            commands: &commands,
            projection: projection
        )
        addFurniture(
            commands: &commands,
            projection: projection
        )
        addWalls(
            commands: &commands,
            projection: projection
        )
        addOpenings(
            commands: &commands,
            projection: projection
        )
        addElectrical(
            commands: &commands,
            projection: projection
        )
        addCeilingLighting(
            commands: &commands,
            projection: projection
        )
        addAnnotations(
            commands: &commands,
            projection: projection
        )
        return Data(commands.render().utf8)
    }

    private func addFloors(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        for floor in record.project.floors ?? [] {
            let points = ExportGeometry.floorCorners(
                matrix: floor.matrix,
                width: floor.width,
                depth: floor.depth
            ).map(projection.map)
            commands.polygon(
                layer: "FLOOR",
                points: points,
                stroke: RGBColor(0.65, 0.67, 0.70),
                fill: RGBColor(0.88, 0.89, 0.91),
                width: 1.2
            )
        }
    }

    private func addFurniture(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        for object in record.project.objects ?? [] {
            let points = ExportGeometry.objectCorners(
                matrix: object.matrix,
                width: object.width,
                depth: object.depth
            ).map(projection.map)
            commands.polygon(
                layer: "FURNITURE",
                points: points,
                stroke: RGBColor(0.47, 0.49, 0.52),
                fill: RGBColor(0.83, 0.84, 0.86),
                width: 1
            )
            commands.vectorText(
                layer: "ANNOTATIONS",
                value: object.title,
                at: projection.map(
                    ExportGeometry.center(object.matrix)
                ),
                size: 7.5,
                color: RGBColor(0.25, 0.25, 0.27)
            )
        }
    }

    private func addWalls(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        for (index, wall) in record.project.walls.enumerated() {
            let ends = ExportGeometry.lineEndpoints(
                matrix: wall.matrix,
                width: wall.width
            )
            let firstCAD = cadPoint(ends.0)
            let secondCAD = cadPoint(ends.1)
            commands.line(
                layer: "WALLS",
                from: projection.mapCAD(firstCAD),
                to: projection.mapCAD(secondCAD),
                color: RGBColor(0.07, 0.38, 0.64),
                width: max(2.5, projection.scale * 0.04)
            )
            commands.dimension(
                layer: "DIM_WALLS",
                from: firstCAD,
                to: secondCAD,
                offset: 0.16,
                label: String(format: "%.2f m", wall.width),
                projection: projection,
                color: RGBColor(0.07, 0.38, 0.64)
            )
            let center = midpoint(
                projection.mapCAD(firstCAD),
                projection.mapCAD(secondCAD)
            )
            commands.vectorText(
                layer: "ANNOTATIONS",
                value: "W\(index + 1)",
                at: CGPoint(x: center.x, y: center.y - 8),
                size: 6.5,
                color: RGBColor(0.18, 0.18, 0.20)
            )
        }
    }

    private func addOpenings(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        for surface in record.project.surfaces {
            let ends = ExportGeometry.lineEndpoints(
                matrix: surface.matrix,
                width: surface.width
            )
            let first = projection.mapCAD(cadPoint(ends.0))
            let second = projection.mapCAD(cadPoint(ends.1))
            let layer: String
            let color: RGBColor
            switch surface.kind {
            case .door:
                layer = "DOORS"
                color = RGBColor(1.00, 0.48, 0.10)
            case .window:
                layer = "WINDOWS"
                color = RGBColor(0.18, 0.68, 0.88)
            case .opening:
                layer = "OPENINGS"
                color = RGBColor(0.62, 0.28, 0.78)
            }
            commands.line(
                layer: layer,
                from: first,
                to: second,
                color: color,
                width: max(4, projection.scale * 0.065)
            )
            commands.vectorText(
                layer: "ANNOTATIONS",
                value: "\(ExportGeometry.surfaceTitle(surface.kind)) \(String(format: "%.2f", surface.width))m",
                at: CGPoint(
                    x: (first.x + second.x) / 2,
                    y: (first.y + second.y) / 2 + 11
                ),
                size: 7,
                color: color,
                rotation: textAngle(from: first, to: second)
            )
        }
    }

    private func addElectrical(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        for point in record.project.points {
            guard let planPosition = ExportGeometry.electricalPosition(
                point,
                project: record.project
            ) else {
                continue
            }
            let centerCAD = cadPoint(planPosition)
            let center = projection.mapCAD(centerCAD)
            let layer = point.status == .existing
                ? "ELECTRICAL_EXISTING"
                : "ELECTRICAL_PROPOSED"
            let color = point.status == .existing
                ? RGBColor(0.18, 0.72, 0.30)
                : RGBColor(1.00, 0.55, 0.08)
            commands.circle(
                layer: layer,
                center: center,
                radius: max(3.2, projection.scale * 0.045),
                stroke: color,
                fill: color,
                width: 0.8
            )
            commands.vectorText(
                layer: layer,
                value: ExportGeometry.shortElectricalTitle(point.type),
                at: CGPoint(x: center.x, y: center.y + 10),
                size: 6.5,
                color: color
            )

            guard let wall = record.project.walls.first(
                where: { $0.id == point.wallID }
            ) else {
                continue
            }
            let wallEnds = ExportGeometry.lineEndpoints(
                matrix: wall.matrix,
                width: wall.width
            )
            let first = cadPoint(wallEnds.0)
            let second = cadPoint(wallEnds.1)
            commands.dimension(
                layer: "DIM_ELECTRICAL",
                from: first,
                to: centerCAD,
                offset: 0.28,
                label: String(
                    format: "%.2f m",
                    max(0, point.localX + wall.width / 2)
                ),
                projection: projection,
                color: RGBColor(0.36, 0.20, 0.74)
            )
            commands.dimension(
                layer: "DIM_ELECTRICAL",
                from: centerCAD,
                to: second,
                offset: 0.40,
                label: String(
                    format: "%.2f m",
                    max(0, wall.width / 2 - point.localX)
                ),
                projection: projection,
                color: RGBColor(0.36, 0.20, 0.74)
            )
        }
    }

    private func addCeilingLighting(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        let stroke = RGBColor(0.95, 0.58, 0.05)
        let fill = RGBColor(1.00, 0.82, 0.10)
        for light in record.project.ceilingLights ?? [] {
            guard light.worldPosition.count >= 3 else { continue }
            let center = projection.mapCAD(
                (
                    Double(light.worldPosition[0]),
                    Double(-light.worldPosition[2])
                )
            )
            let radius = max(
                3.2,
                CGFloat(light.diameterMeters)
                    * projection.scale / 2
            )
            commands.circle(
                layer: "CEILING_LIGHTING",
                center: center,
                radius: radius,
                stroke: stroke,
                fill: fill,
                width: 0.8
            )
            commands.line(
                layer: "CEILING_LIGHTING",
                from: CGPoint(x: center.x - radius, y: center.y),
                to: CGPoint(x: center.x + radius, y: center.y),
                color: stroke,
                width: 0.7
            )
            commands.line(
                layer: "CEILING_LIGHTING",
                from: CGPoint(x: center.x, y: center.y - radius),
                to: CGPoint(x: center.x, y: center.y + radius),
                color: stroke,
                width: 0.7
            )
        }
    }

    private func addAnnotations(
        commands: inout PDFLayerCommands,
        projection: PDFPlanProjection
    ) {
        commands.vectorText(
            layer: "ANNOTATIONS",
            value: metadata.brandName,
            at: projection.mapCAD(
                (
                    projection.minimumX,
                    projection.maximumY + 0.62
                )
            ),
            size: 15,
            color: RGBColor(0.10, 0.10, 0.12),
            alignment: .left
        )
        commands.vectorText(
            layer: "ANNOTATIONS",
            value: metadata.projectLine,
            at: projection.mapCAD(
                (
                    projection.minimumX,
                    projection.maximumY + 0.42
                )
            ),
            size: 8,
            color: RGBColor(0.35, 0.35, 0.38),
            alignment: .left
        )
        commands.vectorText(
            layer: "ANNOTATIONS",
            value: title,
            at: projection.mapCAD(
                (
                    projection.minimumX,
                    projection.maximumY + 0.20
                )
            ),
            size: 11,
            color: RGBColor(0.10, 0.10, 0.12),
            alignment: .left
        )
        if !record.location.isEmpty {
            commands.vectorText(
                layer: "ANNOTATIONS",
                value: record.location,
                at: projection.mapCAD(
                    (
                        projection.minimumX,
                        projection.minimumY - 0.36
                    )
                ),
                size: 7,
                color: RGBColor(0.35, 0.35, 0.38),
                alignment: .left
            )
        }
        commands.vectorText(
            layer: "ANNOTATIONS",
            value: metadata.exportLine,
            at: projection.mapCAD(
                (
                    projection.maximumX,
                    projection.minimumY - 0.36
                )
            ),
            size: 7,
            color: RGBColor(0.35, 0.35, 0.38),
            alignment: .right
        )
    }

    private func cadPoint(
        _ point: SIMD2<Float>
    ) -> (x: Double, y: Double) {
        (Double(point.x), Double(-point.y))
    }

    private func midpoint(
        _ first: CGPoint,
        _ second: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2
        )
    }

    private func textAngle(
        from first: CGPoint,
        to second: CGPoint
    ) -> CGFloat {
        var angle = atan2(
            second.y - first.y,
            second.x - first.x
        )
        if angle > .pi / 2 || angle < -.pi / 2 {
            angle += .pi
        }
        return angle
    }
}

private struct PDFPlanProjection {
    let minimumX: Double
    let maximumX: Double
    let minimumY: Double
    let maximumY: Double
    let scale: CGFloat
    private let offsetX: CGFloat
    private let offsetY: CGFloat

    init?(
        project: RoomProject,
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) {
        let points = ExportGeometry.allPlanPoints(in: project)
        let cadPoints = points.compactMap {
            point -> (x: Double, y: Double)? in
            let x = Double(point.x)
            let y = Double(-point.y)
            guard x.isFinite, y.isFinite else {
                return nil
            }
            return (x: x, y: y)
        }
        guard !cadPoints.isEmpty else { return nil }
        let rawMinimumX = cadPoints.reduce(
            cadPoints[0].x
        ) { min($0, $1.x) }
        let rawMaximumX = cadPoints.reduce(
            cadPoints[0].x
        ) { max($0, $1.x) }
        let rawMinimumY = cadPoints.reduce(
            cadPoints[0].y
        ) { min($0, $1.y) }
        let rawMaximumY = cadPoints.reduce(
            cadPoints[0].y
        ) { max($0, $1.y) }
        let paddingMeters = 0.80
        let minimumX = rawMinimumX - paddingMeters
        let maximumX = rawMaximumX + paddingMeters
        let minimumY = rawMinimumY - paddingMeters
        let maximumY = rawMaximumY + paddingMeters
        let drawingWidth = max(maximumX - minimumX, 0.5)
        let drawingHeight = max(maximumY - minimumY, 0.5)
        let pageMargin: CGFloat = 30
        let availableWidth = pageWidth - pageMargin * 2
        let availableHeight = pageHeight - pageMargin * 2
        let scale = min(
            availableWidth / CGFloat(drawingWidth),
            availableHeight / CGFloat(drawingHeight)
        )
        let renderedWidth = CGFloat(drawingWidth) * scale
        let renderedHeight = CGFloat(drawingHeight) * scale

        self.minimumX = rawMinimumX
        self.maximumX = rawMaximumX
        self.minimumY = rawMinimumY
        self.maximumY = rawMaximumY
        self.scale = scale
        offsetX = pageMargin
            + (availableWidth - renderedWidth) / 2
            - CGFloat(minimumX) * scale
        offsetY = pageMargin
            + (availableHeight - renderedHeight) / 2
            - CGFloat(minimumY) * scale
    }

    func map(_ point: SIMD2<Float>) -> CGPoint {
        mapCAD((Double(point.x), Double(-point.y)))
    }

    func mapCAD(
        _ point: (x: Double, y: Double)
    ) -> CGPoint {
        CGPoint(
            x: offsetX + CGFloat(point.x) * scale,
            y: offsetY + CGFloat(point.y) * scale
        )
    }
}

private enum PDFTextAlignment: Equatable {
    case left
    case center
    case right
}

private struct RGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var strokeCommand: String {
        "\(pdfNumber(red)) \(pdfNumber(green)) \(pdfNumber(blue)) RG"
    }

    var fillCommand: String {
        "\(pdfNumber(red)) \(pdfNumber(green)) \(pdfNumber(blue)) rg"
    }
}

private struct PDFLayerCommands {
    let layerNames: [String]
    private var baseCommands = ""
    private var commands: [String: String] = [:]

    init(layerNames: [String]) {
        self.layerNames = layerNames
        for name in layerNames {
            commands[name] = ""
        }
    }

    mutating func base(_ value: String) {
        baseCommands += value
    }

    mutating func line(
        layer: String,
        from first: CGPoint,
        to second: CGPoint,
        color: RGBColor,
        width: CGFloat
    ) {
        guard first.x.isFinite,
              first.y.isFinite,
              second.x.isFinite,
              second.y.isFinite,
              width.isFinite,
              width >= 0 else {
            return
        }
        append(
            layer: layer,
            """
            q \(color.strokeCommand) \(pdfNumber(width)) w 1 J 1 j
            \(pdfNumber(first.x)) \(pdfNumber(first.y)) m
            \(pdfNumber(second.x)) \(pdfNumber(second.y)) l S Q

            """
        )
    }

    mutating func polygon(
        layer: String,
        points: [CGPoint],
        stroke: RGBColor,
        fill: RGBColor?,
        width: CGFloat
    ) {
        guard points.count >= 2,
              points.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite
              }),
              width.isFinite,
              width >= 0,
              let first = points.first else {
            return
        }
        var value = """
        q \(stroke.strokeCommand) \(fill?.fillCommand ?? "") \(pdfNumber(width)) w 1 J 1 j
        \(pdfNumber(first.x)) \(pdfNumber(first.y)) m

        """
        for point in points.dropFirst() {
            value += "\(pdfNumber(point.x)) \(pdfNumber(point.y)) l\n"
        }
        value += fill == nil ? "h S Q\n" : "h B Q\n"
        append(layer: layer, value)
    }

    mutating func circle(
        layer: String,
        center: CGPoint,
        radius: CGFloat,
        stroke: RGBColor,
        fill: RGBColor?,
        width: CGFloat
    ) {
        guard center.x.isFinite,
              center.y.isFinite,
              radius.isFinite,
              radius > 0,
              width.isFinite,
              width >= 0 else {
            return
        }
        let kappa = radius * 0.5522847498
        let x = center.x
        let y = center.y
        var value = """
        q \(stroke.strokeCommand) \(fill?.fillCommand ?? "") \(pdfNumber(width)) w
        \(pdfNumber(x + radius)) \(pdfNumber(y)) m
        \(pdfNumber(x + radius)) \(pdfNumber(y + kappa)) \(pdfNumber(x + kappa)) \(pdfNumber(y + radius)) \(pdfNumber(x)) \(pdfNumber(y + radius)) c
        \(pdfNumber(x - kappa)) \(pdfNumber(y + radius)) \(pdfNumber(x - radius)) \(pdfNumber(y + kappa)) \(pdfNumber(x - radius)) \(pdfNumber(y)) c
        \(pdfNumber(x - radius)) \(pdfNumber(y - kappa)) \(pdfNumber(x - kappa)) \(pdfNumber(y - radius)) \(pdfNumber(x)) \(pdfNumber(y - radius)) c
        \(pdfNumber(x + kappa)) \(pdfNumber(y - radius)) \(pdfNumber(x + radius)) \(pdfNumber(y - kappa)) \(pdfNumber(x + radius)) \(pdfNumber(y)) c

        """
        value += fill == nil ? "S Q\n" : "B Q\n"
        append(layer: layer, value)
    }

    mutating func vectorText(
        layer: String,
        value: String,
        at center: CGPoint,
        size: CGFloat,
        color: RGBColor,
        rotation: CGFloat = 0,
        alignment: PDFTextAlignment = .center
    ) {
        guard center.x.isFinite,
              center.y.isFinite,
              size.isFinite,
              size > 0,
              rotation.isFinite else {
            return
        }
        guard let path = VectorTextPath.make(
            value,
            size: size,
            center: center,
            rotation: rotation,
            alignment: alignment
        ) else {
            return
        }
        let pathCommands = PDFPathEncoder.encode(path)
        append(
            layer: layer,
            "q \(color.fillCommand)\n\(pathCommands)f Q\n"
        )
    }

    mutating func dimension(
        layer: String,
        from first: (x: Double, y: Double),
        to second: (x: Double, y: Double),
        offset: Double,
        label: String,
        projection: PDFPlanProjection,
        color: RGBColor
    ) {
        guard first.x.isFinite,
              first.y.isFinite,
              second.x.isFinite,
              second.y.isFinite,
              offset.isFinite else {
            return
        }
        let dx = second.x - first.x
        let dy = second.y - first.y
        let length = max(hypot(dx, dy), 0.0001)
        let perpendicular = (
            x: -dy / length * offset,
            y: dx / length * offset
        )
        let dimensionStart = (
            x: first.x + perpendicular.x,
            y: first.y + perpendicular.y
        )
        let dimensionEnd = (
            x: second.x + perpendicular.x,
            y: second.y + perpendicular.y
        )
        let firstPage = projection.mapCAD(first)
        let secondPage = projection.mapCAD(second)
        let dimensionStartPage = projection.mapCAD(dimensionStart)
        let dimensionEndPage = projection.mapCAD(dimensionEnd)
        line(
            layer: layer,
            from: firstPage,
            to: dimensionStartPage,
            color: color,
            width: 0.55
        )
        line(
            layer: layer,
            from: secondPage,
            to: dimensionEndPage,
            color: color,
            width: 0.55
        )
        line(
            layer: layer,
            from: dimensionStartPage,
            to: dimensionEndPage,
            color: color,
            width: 0.65
        )

        let tickLength = max(3.2, projection.scale * 0.045)
        let pageDX = dimensionEndPage.x - dimensionStartPage.x
        let pageDY = dimensionEndPage.y - dimensionStartPage.y
        let pageLength = max(hypot(pageDX, pageDY), 0.001)
        let tangent = CGPoint(
            x: pageDX / pageLength,
            y: pageDY / pageLength
        )
        let diagonal = CGPoint(
            x: (tangent.x - tangent.y) * tickLength,
            y: (tangent.y + tangent.x) * tickLength
        )
        line(
            layer: layer,
            from: CGPoint(
                x: dimensionStartPage.x - diagonal.x,
                y: dimensionStartPage.y - diagonal.y
            ),
            to: CGPoint(
                x: dimensionStartPage.x + diagonal.x,
                y: dimensionStartPage.y + diagonal.y
            ),
            color: color,
            width: 0.65
        )
        line(
            layer: layer,
            from: CGPoint(
                x: dimensionEndPage.x - diagonal.x,
                y: dimensionEndPage.y - diagonal.y
            ),
            to: CGPoint(
                x: dimensionEndPage.x + diagonal.x,
                y: dimensionEndPage.y + diagonal.y
            ),
            color: color,
            width: 0.65
        )

        var rotation = atan2(pageDY, pageDX)
        if rotation > .pi / 2 || rotation < -.pi / 2 {
            rotation += .pi
        }
        vectorText(
            layer: layer,
            value: label,
            at: CGPoint(
                x: (dimensionStartPage.x + dimensionEndPage.x) / 2,
                y: (dimensionStartPage.y + dimensionEndPage.y) / 2 + 4
            ),
            size: 6.5,
            color: color,
            rotation: rotation
        )
    }

    func render() -> String {
        var result = baseCommands
        for (index, layer) in layerNames.enumerated() {
            result += "q /OC /L\(index + 1) BDC\n"
            result += commands[layer] ?? ""
            result += "EMC Q\n"
        }
        return result
    }

    private mutating func append(
        layer: String,
        _ value: String
    ) {
        commands[layer, default: ""] += value
    }
}

private enum VectorTextPath {
    static func make(
        _ value: String,
        size: CGFloat,
        center: CGPoint,
        rotation: CGFloat,
        alignment: PDFTextAlignment
    ) -> CGPath? {
        guard !value.isEmpty else { return nil }
        let uiFont = UIFont.systemFont(ofSize: size)
        let font = CTFontCreateWithName(
            uiFont.fontName as CFString,
            size,
            nil
        )
        let attributed = NSAttributedString(
            string: value,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(
            CTLineGetTypographicBounds(
                line,
                &ascent,
                &descent,
                &leading
            )
        )
        let horizontalOffset: CGFloat
        switch alignment {
        case .left:
            horizontalOffset = 0
        case .center:
            horizontalOffset = -width / 2
        case .right:
            horizontalOffset = -width
        }
        let verticalOffset = -(ascent - descent) / 2
        let combined = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[
                kCTFontAttributeName
            ] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = Array(
                repeating: CGGlyph(),
                count: count
            )
            var positions = Array(
                repeating: CGPoint.zero,
                count: count
            )
            CTRunGetGlyphs(
                run,
                CFRange(location: 0, length: 0),
                &glyphs
            )
            CTRunGetPositions(
                run,
                CFRange(location: 0, length: 0),
                &positions
            )
            for index in 0..<count {
                guard let glyphPath = CTFontCreatePathForGlyph(
                    runFont,
                    glyphs[index],
                    nil
                ) else {
                    continue
                }
                let transform = CGAffineTransform(
                    translationX: horizontalOffset
                        + positions[index].x,
                    y: verticalOffset + positions[index].y
                )
                combined.addPath(
                    glyphPath,
                    transform: transform
                )
            }
        }

        var finalTransform = CGAffineTransform(
            translationX: center.x,
            y: center.y
        )
        finalTransform = finalTransform.rotated(by: rotation)
        return combined.copy(using: &finalTransform)
    }
}

private enum PDFPathEncoder {
    static func encode(_ path: CGPath) -> String {
        var result = ""
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                let point = element.points[0]
                result += "\(pdfNumber(point.x)) \(pdfNumber(point.y)) m\n"
                current = point
                subpathStart = point
            case .addLineToPoint:
                let point = element.points[0]
                result += "\(pdfNumber(point.x)) \(pdfNumber(point.y)) l\n"
                current = point
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                let firstControl = CGPoint(
                    x: current.x
                        + (control.x - current.x) * 2 / 3,
                    y: current.y
                        + (control.y - current.y) * 2 / 3
                )
                let secondControl = CGPoint(
                    x: end.x + (control.x - end.x) * 2 / 3,
                    y: end.y + (control.y - end.y) * 2 / 3
                )
                result += """
                \(pdfNumber(firstControl.x)) \(pdfNumber(firstControl.y)) \(pdfNumber(secondControl.x)) \(pdfNumber(secondControl.y)) \(pdfNumber(end.x)) \(pdfNumber(end.y)) c

                """
                current = end
            case .addCurveToPoint:
                let firstControl = element.points[0]
                let secondControl = element.points[1]
                let end = element.points[2]
                result += """
                \(pdfNumber(firstControl.x)) \(pdfNumber(firstControl.y)) \(pdfNumber(secondControl.x)) \(pdfNumber(secondControl.y)) \(pdfNumber(end.x)) \(pdfNumber(end.y)) c

                """
                current = end
            case .closeSubpath:
                result += "h\n"
                current = subpathStart
            @unknown default:
                break
            }
        }
        return result
    }
}

private func pdfNumber<T: BinaryFloatingPoint>(_ value: T) -> String {
    guard value.isFinite else {
        return "0"
    }
    return String(format: "%.4f", Double(value))
}

private func pdfEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: ")", with: "\\)")
}

private func pdfDate(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMddHHmmss'Z'"
    return formatter.string(from: value)
}
