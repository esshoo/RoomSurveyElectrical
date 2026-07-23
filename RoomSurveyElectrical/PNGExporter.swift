import Foundation
import simd
import UIKit

extension ProjectExportService {
    static func makePlanPNG(
        title: String,
        room: ExportRoomRecord,
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        let data = PNGPlanRenderer(
            title: title,
            record: room,
            metadata: metadata
        ).render()
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-2D-full-layers",
            extension: "png"
        )
    }

    static func makePlanPNGPackage(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        if rooms.count == 1 {
            return try makePlanPNG(
                title: title,
                room: rooms[0],
                metadata: metadata
            )
        }

        var archive = StoredZIPArchive()
        for (index, room) in rooms.enumerated() {
            let name = String(
                format: "%02d-%@-2D.png",
                index + 1,
                sanitized(room.scan.name)
            )
            archive.add(
                name: name,
                data: PNGPlanRenderer(
                    title: room.scan.name,
                    record: room,
                    metadata: metadata
                ).render()
            )
        }
        return try writeTemporaryFile(
            archive.data(),
            name: "\(sanitized(title))-PNG",
            extension: "zip"
        )
    }
}

private struct PNGPlanRenderer {
    let title: String
    let record: ExportRoomRecord
    let metadata: ExportDocumentMetadata

    private let canvasSize = CGSize(width: 3000, height: 2121)
    private let accent = UIColor(
        red: 18 / 255,
        green: 98 / 255,
        blue: 163 / 255,
        alpha: 1
    )

    func render() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: canvasSize,
            format: format
        )
        return renderer.pngData { rendererContext in
            let context = rendererContext.cgContext
            UIColor.white.setFill()
            context.fill(
                CGRect(origin: .zero, size: canvasSize)
            )
            drawHeader(context: context)
            drawLegend(context: context)
            drawExportFooter()
            drawPlan(context: context)
        }
    }

    private func drawHeader(context: CGContext) {
        let rect = CGRect(
            x: 60,
            y: 50,
            width: canvasSize.width - 120,
            height: 155
        )
        context.setFillColor(accent.cgColor)
        context.fill(rect)
        exportDrawText(
            metadata.brandName,
            in: CGRect(
                x: rect.minX + 35,
                y: rect.minY + 18,
                width: 600,
                height: 46
            ),
            font: .boldSystemFont(ofSize: 32),
            color: .white,
            alignment: .left
        )
        exportDrawText(
            metadata.projectName,
            in: CGRect(
                x: rect.minX + 35,
                y: rect.minY + 62,
                width: rect.width / 2 - 70,
                height: 34
            ),
            font: .boldSystemFont(ofSize: 23),
            color: UIColor.white.withAlphaComponent(0.95),
            alignment: .left
        )
        exportDrawText(
            "تاريخ الإنشاء: \(metadata.projectCreatedText)",
            in: CGRect(
                x: rect.minX + 35,
                y: rect.minY + 100,
                width: rect.width / 2 - 70,
                height: 28
            ),
            font: .systemFont(ofSize: 18),
            color: UIColor.white.withAlphaComponent(0.82),
            alignment: .left
        )
        exportDrawText(
            "PNG 2D – كامل الطبقات",
            in: CGRect(
                x: rect.midX,
                y: rect.minY + 18,
                width: rect.width / 2 - 35,
                height: 44
            ),
            font: .boldSystemFont(ofSize: 34),
            color: .white
        )
        exportDrawText(
            title,
            in: CGRect(
                x: rect.midX,
                y: rect.minY + 68,
                width: rect.width / 2 - 35,
                height: 32
            ),
            font: .systemFont(ofSize: 22),
            color: UIColor.white.withAlphaComponent(0.92)
        )
        exportDrawText(
            record.location.isEmpty ? "المشروع" : record.location,
            in: CGRect(
                x: rect.midX,
                y: rect.minY + 108,
                width: rect.width / 2 - 35,
                height: 27
            ),
            font: .systemFont(ofSize: 18),
            color: UIColor.white.withAlphaComponent(0.82)
        )
    }

    private func drawExportFooter() {
        exportDrawText(
            metadata.exportLine,
            in: CGRect(
                x: canvasSize.width - 950,
                y: canvasSize.height - 42,
                width: 875,
                height: 28
            ),
            font: .systemFont(ofSize: 17),
            color: .darkGray
        )
    }

    private func drawLegend(context: CGContext) {
        let legend = CGRect(
            x: 75,
            y: canvasSize.height - 105,
            width: canvasSize.width - 150,
            height: 58
        )
        context.setFillColor(
            UIColor(white: 0.96, alpha: 1).cgColor
        )
        context.fill(legend)
        let values: [(String, UIColor)] = [
            ("حوائط", accent),
            ("أبواب", .systemOrange),
            ("شبابيك", .systemCyan),
            ("فرش", .systemGray),
            ("كهرباء موجود", .systemGreen),
            ("كهرباء مقترح", .systemOrange),
            ("إضاءة سقف", .systemYellow),
            ("أبعاد", .systemIndigo)
        ]
        let itemWidth = legend.width / CGFloat(values.count)
        for (index, value) in values.enumerated() {
            let x = legend.minX + CGFloat(index) * itemWidth
            context.setFillColor(value.1.cgColor)
            context.fillEllipse(
                in: CGRect(
                    x: x + itemWidth - 32,
                    y: legend.midY - 9,
                    width: 18,
                    height: 18
                )
            )
            exportDrawText(
                value.0,
                in: CGRect(
                    x: x + 8,
                    y: legend.minY + 15,
                    width: itemWidth - 47,
                    height: 28
                ),
                font: .systemFont(ofSize: 17),
                color: .darkGray
            )
        }
    }

    private func drawPlan(context: CGContext) {
        let drawingRect = CGRect(
            x: 85,
            y: 235,
            width: canvasSize.width - 170,
            height: canvasSize.height - 375
        )
        context.setStrokeColor(
            UIColor(white: 0.83, alpha: 1).cgColor
        )
        context.setLineWidth(2)
        context.stroke(drawingRect)

        guard let projection = ExportPlanProjection(
            project: record.project,
            targetRect: drawingRect.insetBy(dx: 95, dy: 95)
        ) else {
            exportDrawText(
                "لا توجد هندسة صالحة للرسم.",
                in: drawingRect,
                font: .boldSystemFont(ofSize: 36),
                color: .gray,
                alignment: .center
            )
            return
        }

        context.saveGState()
        context.clip(to: drawingRect.insetBy(dx: 3, dy: 3))
        drawGrid(
            context: context,
            rect: drawingRect,
            scale: projection.scale
        )
        drawFloors(context: context, projection: projection)
        drawFurniture(context: context, projection: projection)
        drawWalls(context: context, projection: projection)
        drawOpenings(context: context, projection: projection)
        drawElectrical(context: context, projection: projection)
        drawCeilingLighting(
            context: context,
            projection: projection
        )
        context.restoreGState()
    }

    private func drawGrid(
        context: CGContext,
        rect: CGRect,
        scale: CGFloat
    ) {
        let spacing = max(scale, 45)
        context.setStrokeColor(
            UIColor(white: 0.94, alpha: 1).cgColor
        )
        context.setLineWidth(1)
        var x = rect.minX
        while x <= rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        context.strokePath()
    }

    private func drawFloors(
        context: CGContext,
        projection: ExportPlanProjection
    ) {
        for floor in record.project.floors ?? [] {
            drawPolygon(
                ExportGeometry.floorCorners(
                    matrix: floor.matrix,
                    width: floor.width,
                    depth: floor.depth
                ).map(projection.map),
                context: context,
                fill: UIColor(white: 0.89, alpha: 0.68),
                stroke: UIColor(white: 0.66, alpha: 1),
                width: 3
            )
        }
    }

    private func drawFurniture(
        context: CGContext,
        projection: ExportPlanProjection
    ) {
        for object in record.project.objects ?? [] {
            let corners = ExportGeometry.objectCorners(
                matrix: object.matrix,
                width: object.width,
                depth: object.depth
            ).map(projection.map)
            drawPolygon(
                corners,
                context: context,
                fill: .systemGray5,
                stroke: .systemGray,
                width: 3
            )
            drawCenteredLabel(
                object.title,
                at: projection.map(
                    ExportGeometry.center(object.matrix)
                ),
                color: .darkGray
            )
        }
    }

    private func drawWalls(
        context: CGContext,
        projection: ExportPlanProjection
    ) {
        for wall in record.project.walls {
            let ends = ExportGeometry.lineEndpoints(
                matrix: wall.matrix,
                width: wall.width
            )
            let first = projection.map(ends.0)
            let second = projection.map(ends.1)
            drawLine(
                context: context,
                first: first,
                second: second,
                color: accent,
                width: 11
            )
            drawDimensionLabel(
                String(format: "%.2f م", wall.width),
                at: midpoint(first, second),
                color: accent
            )
        }
    }

    private func drawOpenings(
        context: CGContext,
        projection: ExportPlanProjection
    ) {
        for surface in record.project.surfaces {
            let ends = ExportGeometry.lineEndpoints(
                matrix: surface.matrix,
                width: surface.width
            )
            let first = projection.map(ends.0)
            let second = projection.map(ends.1)
            let color: UIColor
            switch surface.kind {
            case .door: color = .systemOrange
            case .window: color = .systemCyan
            case .opening: color = .systemPurple
            }
            drawLine(
                context: context,
                first: first,
                second: second,
                color: color,
                width: 16
            )
            drawDimensionLabel(
                "\(ExportGeometry.surfaceTitle(surface.kind)) \(String(format: "%.2f", surface.width)) م",
                at: CGPoint(
                    x: (first.x + second.x) / 2,
                    y: (first.y + second.y) / 2 + 29
                ),
                color: color
            )
        }
    }

    private func drawElectrical(
        context: CGContext,
        projection: ExportPlanProjection
    ) {
        for point in record.project.points {
            guard let planPosition = ExportGeometry.electricalPosition(
                point,
                project: record.project
            ) else {
                continue
            }
            let center = projection.map(planPosition)
            let color = uiColor(
                hex: point.colorHex,
                fallback: point.status == .existing
                    ? .systemGreen
                    : .systemOrange
            )
            context.setFillColor(color.cgColor)
            context.fillEllipse(
                in: CGRect(
                    x: center.x - 12,
                    y: center.y - 12,
                    width: 24,
                    height: 24
                )
            )
            drawCenteredLabel(
                ExportGeometry.shortElectricalTitle(point.type),
                at: CGPoint(x: center.x, y: center.y - 30),
                color: color,
                width: 240
            )
            if let wall = record.project.walls.first(
                where: { $0.id == point.wallID }
            ) {
                drawDimensionLabel(
                    String(
                        format: "%.2f | %.2f م",
                        max(0, point.localX + wall.width / 2),
                        max(0, wall.width / 2 - point.localX)
                    ),
                    at: CGPoint(
                        x: center.x,
                        y: center.y + 31
                    ),
                    color: .systemIndigo
                )
            }
        }
    }

    private func drawCeilingLighting(
        context: CGContext,
        projection: ExportPlanProjection
    ) {
        for light in record.project.ceilingLights ?? [] {
            guard light.worldPosition.count >= 3 else { continue }
            let center = projection.map(
                SIMD2(
                    light.worldPosition[0],
                    light.worldPosition[2]
                )
            )
            let radius = max(
                10,
                CGFloat(light.diameterMeters)
                    * projection.scale / 2
            )
            let color = uiColor(
                hex: light.colorHex,
                fallback: .systemYellow
            )
            context.setFillColor(
                color.withAlphaComponent(
                    CGFloat(max(light.brightness, 0.25))
                ).cgColor
            )
            context.fillEllipse(
                in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            drawLine(
                context: context,
                first: CGPoint(x: center.x - radius, y: center.y),
                second: CGPoint(x: center.x + radius, y: center.y),
                color: .systemOrange,
                width: 3
            )
            drawLine(
                context: context,
                first: CGPoint(x: center.x, y: center.y - radius),
                second: CGPoint(x: center.x, y: center.y + radius),
                color: .systemOrange,
                width: 3
            )
        }
    }

    private func drawPolygon(
        _ points: [CGPoint],
        context: CGContext,
        fill: UIColor,
        stroke: UIColor,
        width: CGFloat
    ) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.closePath()
        context.setFillColor(fill.cgColor)
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(width)
        context.drawPath(using: .fillStroke)
    }

    private func drawLine(
        context: CGContext,
        first: CGPoint,
        second: CGPoint,
        color: UIColor,
        width: CGFloat
    ) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: first)
        context.addLine(to: second)
        context.strokePath()
    }

    private func drawDimensionLabel(
        _ value: String,
        at point: CGPoint,
        color: UIColor
    ) {
        let font = UIFont.systemFont(ofSize: 18)
        let size = (value as NSString).size(
            withAttributes: [.font: font]
        )
        let rect = CGRect(
            x: point.x - size.width / 2 - 9,
            y: point.y - 15,
            width: size.width + 18,
            height: 31
        )
        UIColor.white.withAlphaComponent(0.9).setFill()
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: 7
        ).fill()
        exportDrawText(
            value,
            in: rect.insetBy(dx: 6, dy: 5),
            font: font,
            color: color,
            alignment: .center
        )
    }

    private func drawCenteredLabel(
        _ value: String,
        at point: CGPoint,
        color: UIColor,
        width: CGFloat = 180
    ) {
        exportDrawText(
            value,
            in: CGRect(
                x: point.x - width / 2,
                y: point.y - 14,
                width: width,
                height: 28
            ),
            font: .systemFont(ofSize: 17),
            color: color,
            alignment: .center
        )
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

    private func uiColor(
        hex: String?,
        fallback: UIColor
    ) -> UIColor {
        guard let hex else { return fallback }
        let cleaned = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return fallback
        }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func exportDrawText(
    _ value: String,
    in rect: CGRect,
    font: UIFont,
    color: UIColor,
    alignment: NSTextAlignment = .right
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.baseWritingDirection = alignment == .left
        ? .leftToRight
        : .rightToLeft
    paragraph.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}
