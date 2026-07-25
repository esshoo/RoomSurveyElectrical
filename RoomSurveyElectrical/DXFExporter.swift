import Foundation
import simd

extension ProjectExportService {
    private static func validatedDXFData(_ text: String) throws -> Data {
        try DXFCompatibilityValidator.validate(text)
        return Data(text.utf8)
    }

    static func makeDXF(
        title: String,
        room: ExportRoomRecord,
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        let data = try validatedDXFData(
            DXFPlanBuilder(
                title: title,
                record: room,
                metadata: metadata
            ).build()
        )
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-ModelSpace-UTF8-2007",
            extension: "dxf"
        )
    }

    static func makeDXFPackage(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        if rooms.count == 1 {
            return try makeDXF(
                title: title,
                room: rooms[0],
                metadata: metadata
            )
        }

        var archive = StoredZIPArchive()
        for (index, room) in rooms.enumerated() {
            let name = String(
                format: "%02d-%@-ModelSpace-UTF8-2007.dxf",
                index + 1,
                sanitized(room.scan.name)
            )
            archive.add(
                name: name,
                data: try validatedDXFData(
                    DXFPlanBuilder(
                        title: room.scan.name,
                        record: room,
                        metadata: metadata
                    ).build()
                )
            )
        }
        return try writeTemporaryFile(
            archive.data(),
            name: "\(sanitized(title))-DXF",
            extension: "zip"
        )
    }

    static func makeCombinedDXF(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        if rooms.count == 1 {
            return try makeDXF(
                title: title,
                room: rooms[0],
                metadata: metadata
            )
        }
        let data = try validatedDXFData(
            DXFPlanBuilder.combined(
                title: title,
                rooms: rooms,
                metadata: metadata
            )
        )
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-Combined-ModelSpace-UTF8-2007",
            extension: "dxf"
        )
    }

    /// Compatibility alias retained for older callers. Paper Space is not
    /// generated; every room is written as real geometry in Model Space.
    static func makeLayoutDXF(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        let data = try validatedDXFData(
            DXFPlanBuilder.combined(
                title: title,
                rooms: rooms,
                metadata: metadata
            )
        )
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-ModelSpace-UTF8-2007",
            extension: "dxf"
        )
    }
}

private struct DXFPlanBuilder {
    let title: String
    let record: ExportRoomRecord
    let metadata: ExportDocumentMetadata
    var translation: (x: Double, y: Double) = (0, 0)

    private struct Bounds {
        let minimumX: Double
        let maximumX: Double
        let minimumY: Double
        let maximumY: Double

        var width: Double {
            max(maximumX - minimumX, 0.5)
        }

        var height: Double {
            max(maximumY - minimumY, 0.5)
        }
    }

    private struct Placement {
        let room: ExportRoomRecord
        let bounds: Bounds
        let translation: (x: Double, y: Double)
    }

    private let layers: [(name: String, color: Int, lineWeight: Int)] = [
        ("FLOOR", 8, 15),
        ("WALLS", 5, 50),
        ("DOORS", 30, 50),
        ("WINDOWS", 4, 50),
        ("OPENINGS", 6, 50),
        ("FURNITURE", 9, 18),
        ("ELECTRICAL_EXISTING", 3, 25),
        ("ELECTRICAL_PROPOSED", 30, 25),
        ("CEILING_LIGHTING", 2, 25),
        ("DIM_WALLS", 5, 13),
        ("DIM_ELECTRICAL", 6, 13),
        ("ANNOTATIONS", 7, 13)
    ]

    static func combined(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) -> String {
        guard let firstRoom = rooms.first else { return "" }

        let spacing = 2.0
        var cursorX = 0.0
        var maximumHeight = 0.0
        var placements: [Placement] = []

        for room in rooms {
            let roomBounds = bounds(for: room.project)
            let roomTranslation = (
                x: cursorX - roomBounds.minimumX,
                y: -roomBounds.minimumY
            )
            placements.append(
                Placement(
                    room: room,
                    bounds: roomBounds,
                    translation: roomTranslation
                )
            )
            cursorX += roomBounds.width + spacing
            maximumHeight = max(maximumHeight, roomBounds.height)
        }

        let drawingMaximumX = max(cursorX - spacing, 0.5)
        let drawingMaximumY = max(maximumHeight, 0.5)
        let firstBuilder = DXFPlanBuilder(
            title: title,
            record: firstRoom,
            metadata: metadata
        )

        var dxf = DXFWriter()
        dxf.pair(999, "3ERoomElectrical v1.9.9 MODEL_SPACE_UTF8_2007")
        firstBuilder.addHeader(
            to: &dxf,
            bounds: Bounds(
                minimumX: -1,
                maximumX: drawingMaximumX + 1,
                minimumY: -1,
                maximumY: drawingMaximumY + 2
            )
        )
        firstBuilder.addClasses(to: &dxf)
        firstBuilder.addTables(to: &dxf)
        firstBuilder.addBlocks(to: &dxf)
        dxf.beginEntities()

        for placement in placements {
            let builder = DXFPlanBuilder(
                title: placement.room.scan.name,
                record: placement.room,
                metadata: metadata,
                translation: placement.translation
            )
            builder.addEntities(to: &dxf)

            let labelX = placement.bounds.minimumX + placement.translation.x
            let labelY = placement.bounds.maximumY
                + placement.translation.y
                + 0.32
            dxf.text(
                placement.room.scan.name,
                at: (labelX, labelY),
                height: 0.16,
                layer: "ANNOTATIONS",
                horizontalAlignment: 0
            )
            if !placement.room.location.isEmpty {
                dxf.text(
                    placement.room.location,
                    at: (labelX, labelY - 0.18),
                    height: 0.08,
                    layer: "ANNOTATIONS",
                    horizontalAlignment: 0
                )
            }
        }

        dxf.text(
            metadata.brandName,
            at: (0, drawingMaximumY + 1.42),
            height: 0.22,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            metadata.projectLine,
            at: (0, drawingMaximumY + 1.15),
            height: 0.09,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            title,
            at: (0, drawingMaximumY + 0.92),
            height: 0.14,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            metadata.exportLine,
            at: (drawingMaximumX, -0.55),
            height: 0.08,
            layer: "ANNOTATIONS",
            horizontalAlignment: 2
        )

        dxf.endEntitiesAndFile()
        return dxf.output
    }

    static func layouts(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) -> String {
        combined(title: title, rooms: rooms, metadata: metadata)
    }

    func build() -> String {
        var dxf = DXFWriter()
        dxf.pair(999, "3ERoomElectrical v1.9.9 MODEL_SPACE_UTF8_2007")
        addHeader(to: &dxf)
        addClasses(to: &dxf)
        addTables(to: &dxf)
        addBlocks(to: &dxf)
        dxf.beginEntities()
        addEntities(to: &dxf)
        addDrawingInformation(to: &dxf)
        dxf.endEntitiesAndFile()
        return dxf.output
    }

    private func addEntities(to dxf: inout DXFWriter) {
        addFloorEntities(to: &dxf)
        addFurnitureEntities(to: &dxf)
        addWallEntities(to: &dxf)
        addOpeningEntities(to: &dxf)
        addElectricalEntities(to: &dxf)
        addCeilingLightingEntities(to: &dxf)
    }

    private func addHeader(to dxf: inout DXFWriter) {
        let drawingBounds = Self.bounds(for: record.project)
        addHeader(
            to: &dxf,
            bounds: Bounds(
                minimumX: drawingBounds.minimumX + translation.x,
                maximumX: drawingBounds.maximumX + translation.x,
                minimumY: drawingBounds.minimumY + translation.y,
                maximumY: drawingBounds.maximumY + translation.y
            )
        )
    }

    private func addHeader(
        to dxf: inout DXFWriter,
        bounds: Bounds
    ) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "HEADER")
        dxf.pair(9, "$ACADVER")
        dxf.pair(1, "AC1021")
        dxf.pair(9, "$HANDSEED")
        dxf.pair(5, "200000")
        dxf.pair(9, "$DWGCODEPAGE")
        dxf.pair(3, "UTF-8")
        dxf.pair(9, "$INSUNITS")
        dxf.pair(70, 6)
        dxf.pair(9, "$MEASUREMENT")
        dxf.pair(70, 1)
        dxf.pair(9, "$LUNITS")
        dxf.pair(70, 2)
        dxf.pair(9, "$LUPREC")
        dxf.pair(70, 3)
        dxf.pair(9, "$TILEMODE")
        dxf.pair(70, 1)
        dxf.pair(9, "$CTAB")
        dxf.pair(1, "Model")
        dxf.pair(9, "$EXTMIN")
        dxf.pair(10, bounds.minimumX - 1)
        dxf.pair(20, bounds.minimumY - 1)
        dxf.pair(30, 0.0)
        dxf.pair(9, "$EXTMAX")
        dxf.pair(10, bounds.maximumX + 4)
        dxf.pair(20, bounds.maximumY + 1)
        dxf.pair(30, 0.0)
        dxf.pair(0, "ENDSEC")
    }

    private func addClasses(to dxf: inout DXFWriter) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "CLASSES")
        dxf.pair(0, "ENDSEC")
    }

    private func addTables(to dxf: inout DXFWriter) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "TABLES")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "LTYPE")
        dxf.pair(5, "1")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, 1)
        dxf.pair(0, "LTYPE")
        dxf.pair(5, "2")
        dxf.pair(330, "1")
        dxf.pair(100, "AcDbSymbolTableRecord")
        dxf.pair(100, "AcDbLinetypeTableRecord")
        dxf.pair(2, "CONTINUOUS")
        dxf.pair(70, 0)
        dxf.pair(3, "Solid line")
        dxf.pair(72, 65)
        dxf.pair(73, 0)
        dxf.pair(40, 0.0)
        dxf.pair(0, "ENDTAB")

        let allLayers = [(name: "0", color: 7, lineWeight: 15)] + layers
        dxf.pair(0, "TABLE")
        dxf.pair(2, "LAYER")
        dxf.pair(5, "10")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, allLayers.count)
        for (index, layer) in allLayers.enumerated() {
            dxf.pair(0, "LAYER")
            dxf.pair(5, Self.hexHandle(0x11 + index))
            dxf.pair(330, "10")
            dxf.pair(100, "AcDbSymbolTableRecord")
            dxf.pair(100, "AcDbLayerTableRecord")
            dxf.pair(2, layer.name)
            dxf.pair(70, 0)
            dxf.pair(62, layer.color)
            dxf.pair(6, "CONTINUOUS")
            dxf.pair(370, layer.lineWeight)
        }
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "STYLE")
        dxf.pair(5, "20")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, 2)
        addTextStyle(
            to: &dxf,
            handle: "21",
            name: "STANDARD",
            fontFile: "Arial.ttf"
        )
        addTextStyle(
            to: &dxf,
            handle: "22",
            name: "3E_ARABIC",
            fontFile: "Arial.ttf"
        )
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "BLOCK_RECORD")
        dxf.pair(5, "30")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, 2)
        addBlockRecord(to: &dxf, handle: "31", name: "*Model_Space")
        addBlockRecord(to: &dxf, handle: "32", name: "*Paper_Space")
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "ENDSEC")
    }

    private func addTextStyle(
        to dxf: inout DXFWriter,
        handle: String,
        name: String,
        fontFile: String
    ) {
        dxf.pair(0, "STYLE")
        dxf.pair(5, handle)
        dxf.pair(330, "20")
        dxf.pair(100, "AcDbSymbolTableRecord")
        dxf.pair(100, "AcDbTextStyleTableRecord")
        dxf.pair(2, name)
        dxf.pair(70, 0)
        dxf.pair(40, 0.0)
        dxf.pair(41, 1.0)
        dxf.pair(50, 0.0)
        dxf.pair(71, 0)
        dxf.pair(42, 0.2)
        dxf.pair(3, fontFile)
        dxf.pair(4, "")
    }

    private func addBlockRecord(
        to dxf: inout DXFWriter,
        handle: String,
        name: String
    ) {
        dxf.pair(0, "BLOCK_RECORD")
        dxf.pair(5, handle)
        dxf.pair(330, "30")
        dxf.pair(100, "AcDbSymbolTableRecord")
        dxf.pair(100, "AcDbBlockTableRecord")
        dxf.pair(2, name)
        dxf.pair(70, 0)
        dxf.pair(280, 1)
        dxf.pair(281, 0)
    }

    private func addBlocks(to dxf: inout DXFWriter) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "BLOCKS")
        addBlockDefinition(
            to: &dxf,
            name: "*Model_Space",
            owner: "31",
            beginHandle: "33",
            endHandle: "34"
        )
        addBlockDefinition(
            to: &dxf,
            name: "*Paper_Space",
            owner: "32",
            beginHandle: "35",
            endHandle: "36"
        )
        dxf.pair(0, "ENDSEC")
    }

    private func addBlockDefinition(
        to dxf: inout DXFWriter,
        name: String,
        owner: String,
        beginHandle: String,
        endHandle: String
    ) {
        dxf.pair(0, "BLOCK")
        dxf.pair(5, beginHandle)
        dxf.pair(330, owner)
        dxf.pair(100, "AcDbEntity")
        dxf.pair(8, "0")
        dxf.pair(100, "AcDbBlockBegin")
        dxf.pair(2, name)
        dxf.pair(70, 0)
        dxf.pair(10, 0.0)
        dxf.pair(20, 0.0)
        dxf.pair(30, 0.0)
        dxf.pair(3, name)
        dxf.pair(1, "")

        dxf.pair(0, "ENDBLK")
        dxf.pair(5, endHandle)
        dxf.pair(330, owner)
        dxf.pair(100, "AcDbEntity")
        dxf.pair(8, "0")
        dxf.pair(100, "AcDbBlockEnd")
    }

    private static func bounds(for project: RoomProject) -> Bounds {
        let points = ExportGeometry.allPlanPoints(in: project)
            .compactMap { point -> (x: Double, y: Double)? in
                let x = Double(point.x)
                let y = Double(-point.y)
                guard x.isFinite, y.isFinite else { return nil }
                return (x, y)
            }
        guard let first = points.first else {
            return Bounds(
                minimumX: -5,
                maximumX: 5,
                minimumY: -5,
                maximumY: 5
            )
        }
        return Bounds(
            minimumX: points.dropFirst().reduce(first.x) { min($0, $1.x) },
            maximumX: points.dropFirst().reduce(first.x) { max($0, $1.x) },
            minimumY: points.dropFirst().reduce(first.y) { min($0, $1.y) },
            maximumY: points.dropFirst().reduce(first.y) { max($0, $1.y) }
        )
    }

    private static func hexHandle(_ value: Int) -> String {
        String(value, radix: 16).uppercased()
    }

    private func addFloorEntities(to dxf: inout DXFWriter) {
        for floor in record.project.floors ?? [] {
            dxf.polyline(
                ExportGeometry.floorCorners(
                    matrix: floor.matrix,
                    width: floor.width,
                    depth: floor.depth
                ).map(cadPoint),
                layer: "FLOOR",
                closed: true
            )
        }
    }

    private func addFurnitureEntities(to dxf: inout DXFWriter) {
        for object in record.project.objects ?? [] {
            let corners = ExportGeometry.objectCorners(
                matrix: object.matrix,
                width: object.width,
                depth: object.depth
            )
            dxf.polyline(
                corners.map(cadPoint),
                layer: "FURNITURE",
                closed: true
            )
            let center = cadPoint(
                ExportGeometry.center(object.matrix)
            )
            dxf.text(
                object.title,
                at: center,
                height: 0.12,
                layer: "ANNOTATIONS"
            )
        }
    }

    private func addWallEntities(to dxf: inout DXFWriter) {
        for (index, wall) in record.project.walls.enumerated() {
            let endpoints = ExportGeometry.lineEndpoints(
                matrix: wall.matrix,
                width: wall.width
            )
            let first = cadPoint(endpoints.0)
            let second = cadPoint(endpoints.1)
            dxf.line(
                from: first,
                to: second,
                layer: "WALLS"
            )
            dxf.linearDimensionGraphics(
                from: first,
                to: second,
                offset: 0.16,
                label: String(format: "%.2f m", wall.width),
                layer: "DIM_WALLS"
            )
            let center = midpoint(first, second)
            dxf.text(
                "W\(index + 1)",
                at: offset(center, y: -0.10),
                height: 0.09,
                layer: "ANNOTATIONS"
            )
        }
    }

    private func addOpeningEntities(to dxf: inout DXFWriter) {
        for surface in record.project.surfaces {
            let endpoints = ExportGeometry.lineEndpoints(
                matrix: surface.matrix,
                width: surface.width
            )
            let layer: String
            switch surface.kind {
            case .door: layer = "DOORS"
            case .window: layer = "WINDOWS"
            case .opening: layer = "OPENINGS"
            }
            let first = cadPoint(endpoints.0)
            let second = cadPoint(endpoints.1)
            dxf.line(from: first, to: second, layer: layer)
            dxf.text(
                "\(ExportGeometry.surfaceTitle(surface.kind)) \(String(format: "%.2f", surface.width))m",
                at: offset(midpoint(first, second), y: 0.12),
                height: 0.10,
                layer: "ANNOTATIONS",
                rotation: textAngle(from: first, to: second)
            )
        }
    }

    private func addElectricalEntities(to dxf: inout DXFWriter) {
        for point in record.project.points {
            guard let planPosition = ExportGeometry.electricalPosition(
                point,
                project: record.project
            ) else {
                continue
            }
            let center = cadPoint(planPosition)
            let layer = point.status == .existing
                ? "ELECTRICAL_EXISTING"
                : "ELECTRICAL_PROPOSED"
            dxf.circle(
                center: center,
                radius: 0.045,
                layer: layer
            )
            dxf.text(
                ExportGeometry.shortElectricalTitle(point.type),
                at: offset(center, y: 0.10),
                height: 0.08,
                layer: layer
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
            dxf.linearDimensionGraphics(
                from: first,
                to: center,
                offset: 0.28,
                label: String(
                    format: "%.2f m",
                    max(0, point.localX + wall.width / 2)
                ),
                layer: "DIM_ELECTRICAL"
            )
            dxf.linearDimensionGraphics(
                from: center,
                to: second,
                offset: 0.40,
                label: String(
                    format: "%.2f m",
                    max(0, wall.width / 2 - point.localX)
                ),
                layer: "DIM_ELECTRICAL"
            )
        }
    }

    private func addCeilingLightingEntities(
        to dxf: inout DXFWriter
    ) {
        for light in record.project.ceilingLights ?? [] {
            guard light.worldPosition.count >= 3 else { continue }
            let center = cadPoint(
                SIMD2(
                    light.worldPosition[0],
                    light.worldPosition[2]
                )
            )
            let radius = max(
                Double(light.diameterMeters) / 2,
                0.02
            )
            dxf.circle(
                center: center,
                radius: radius,
                layer: "CEILING_LIGHTING"
            )
            dxf.line(
                from: offset(center, x: -radius),
                to: offset(center, x: radius),
                layer: "CEILING_LIGHTING"
            )
            dxf.line(
                from: offset(center, y: -radius),
                to: offset(center, y: radius),
                layer: "CEILING_LIGHTING"
            )
        }
    }

    private func addDrawingInformation(to dxf: inout DXFWriter) {
        let drawingBounds = Self.bounds(for: record.project)
        dxf.text(
            metadata.brandName,
            at: translated(
                (
                    drawingBounds.minimumX,
                    drawingBounds.maximumY + 0.72
                )
            ),
            height: 0.22,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            metadata.projectLine,
            at: translated(
                (
                    drawingBounds.minimumX,
                    drawingBounds.maximumY + 0.48
                )
            ),
            height: 0.09,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            title,
            at: translated(
                (
                    drawingBounds.minimumX,
                    drawingBounds.maximumY + 0.28
                )
            ),
            height: 0.14,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        if !record.location.isEmpty {
            dxf.text(
                record.location,
                at: translated(
                    (
                        drawingBounds.minimumX,
                        drawingBounds.maximumY + 0.10
                    )
                ),
                height: 0.08,
                layer: "ANNOTATIONS",
                horizontalAlignment: 0
            )
        }
        dxf.text(
            metadata.exportLine,
            at: translated(
                (
                    drawingBounds.maximumX,
                    drawingBounds.minimumY - 0.45
                )
            ),
            height: 0.08,
            layer: "ANNOTATIONS",
            horizontalAlignment: 2
        )
    }

    private func cadPoint(
        _ point: SIMD2<Float>
    ) -> (x: Double, y: Double) {
        translated(
            (
                Double(point.x),
                Double(-point.y)
            )
        )
    }

    private func translated(
        _ point: (x: Double, y: Double)
    ) -> (x: Double, y: Double) {
        (
            point.x + translation.x,
            point.y + translation.y
        )
    }

    private func midpoint(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double)
    ) -> (x: Double, y: Double) {
        (
            (first.x + second.x) / 2,
            (first.y + second.y) / 2
        )
    }

    private func offset(
        _ point: (x: Double, y: Double),
        x: Double = 0,
        y: Double = 0
    ) -> (x: Double, y: Double) {
        (point.x + x, point.y + y)
    }

    private func textAngle(
        from first: (x: Double, y: Double),
        to second: (x: Double, y: Double)
    ) -> Double {
        var angle = atan2(
            second.y - first.y,
            second.x - first.x
        ) * 180 / .pi
        if angle > 90 || angle < -90 {
            angle += 180
        }
        return angle
    }
}

private struct DXFWriter {
    private(set) var output = ""
    private var nextEntityHandleValue = 0x100000

    mutating func beginEntities() {
        pair(0, "SECTION")
        pair(2, "ENTITIES")
    }

    mutating func endEntitiesAndFile() {
        pair(0, "ENDSEC")
        pair(0, "EOF")
    }

    mutating func pair(_ code: Int, _ value: String) {
        output += "\(code)\n\(clean(value))\n"
    }

    mutating func pair(_ code: Int, _ value: Int) {
        output += "\(code)\n\(value)\n"
    }

    mutating func pair(_ code: Int, _ value: Double) {
        output += "\(code)\n\(number(value))\n"
    }

    mutating func line(
        from: (x: Double, y: Double),
        to: (x: Double, y: Double),
        layer: String
    ) {
        pair(0, "LINE")
        addEntityHeader(layer: layer, subclass: "AcDbLine")
        pair(10, from.x)
        pair(20, from.y)
        pair(30, 0.0)
        pair(11, to.x)
        pair(21, to.y)
        pair(31, 0.0)
    }

    mutating func polyline(
        _ points: [(x: Double, y: Double)],
        layer: String,
        closed: Bool
    ) {
        guard points.count >= 2 else { return }
        pair(0, "LWPOLYLINE")
        addEntityHeader(layer: layer, subclass: "AcDbPolyline")
        pair(90, points.count)
        pair(70, closed ? 1 : 0)
        for point in points {
            pair(10, point.x)
            pair(20, point.y)
        }
    }

    mutating func circle(
        center: (x: Double, y: Double),
        radius: Double,
        layer: String
    ) {
        pair(0, "CIRCLE")
        addEntityHeader(layer: layer, subclass: "AcDbCircle")
        pair(10, center.x)
        pair(20, center.y)
        pair(30, 0.0)
        pair(40, radius)
    }

    mutating func text(
        _ value: String,
        at point: (x: Double, y: Double),
        height: Double,
        layer: String,
        rotation: Double = 0,
        horizontalAlignment: Int = 1
    ) {
        guard !value.isEmpty else { return }
        if value.unicodeScalars.contains(where: { !$0.isASCII }) {
            mtext(
                value,
                at: point,
                height: height,
                layer: layer,
                rotation: rotation,
                horizontalAlignment: horizontalAlignment
            )
            return
        }

        pair(0, "TEXT")
        addEntityHeader(layer: layer, subclass: "AcDbText")
        pair(10, point.x)
        pair(20, point.y)
        pair(30, 0.0)
        pair(40, height)
        pair(1, value)
        pair(50, rotation)
        pair(41, 1.0)
        pair(7, "STANDARD")
        pair(71, 0)
        pair(72, horizontalAlignment)
        pair(11, point.x)
        pair(21, point.y)
        pair(31, 0.0)
        pair(100, "AcDbText")
        pair(73, 2)
    }

    private mutating func mtext(
        _ value: String,
        at point: (x: Double, y: Double),
        height: Double,
        layer: String,
        rotation: Double,
        horizontalAlignment: Int
    ) {
        pair(0, "MTEXT")
        addEntityHeader(layer: layer, subclass: "AcDbMText")
        pair(10, point.x)
        pair(20, point.y)
        pair(30, 0.0)
        pair(40, height)
        pair(41, max(height * Double(max(value.count, 2)), height * 2))
        switch horizontalAlignment {
        case 0: pair(71, 4)
        case 2: pair(71, 6)
        default: pair(71, 5)
        }
        pair(72, 1)
        addMTextContent(value)
        pair(7, "3E_ARABIC")
        pair(50, rotation)
        pair(73, 1)
        pair(44, 1.0)
    }

    private mutating func addMTextContent(_ value: String) {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\\P")
            .replacingOccurrences(of: "\r", with: "\\P")
            .replacingOccurrences(of: "\n", with: "\\P")
        let chunks = stringChunks(normalized, maximumUTF8Bytes: 240)
        if chunks.count > 1 {
            for chunk in chunks.dropLast() {
                pair(3, chunk)
            }
        }
        pair(1, chunks.last ?? "")
    }

    mutating func linearDimensionGraphics(
        from first: (x: Double, y: Double),
        to second: (x: Double, y: Double),
        offset: Double,
        label: String,
        layer: String
    ) {
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
        line(from: first, to: dimensionStart, layer: layer)
        line(from: second, to: dimensionEnd, layer: layer)
        line(from: dimensionStart, to: dimensionEnd, layer: layer)

        let tickLength = 0.045
        let tangent = (x: dx / length, y: dy / length)
        let normalScale = max(abs(offset), 0.001)
        let tick = (
            x: (tangent.x + perpendicular.x / normalScale) * tickLength,
            y: (tangent.y + perpendicular.y / normalScale) * tickLength
        )
        line(
            from: (
                dimensionStart.x - tick.x,
                dimensionStart.y - tick.y
            ),
            to: (
                dimensionStart.x + tick.x,
                dimensionStart.y + tick.y
            ),
            layer: layer
        )
        line(
            from: (
                dimensionEnd.x - tick.x,
                dimensionEnd.y - tick.y
            ),
            to: (
                dimensionEnd.x + tick.x,
                dimensionEnd.y + tick.y
            ),
            layer: layer
        )

        var rotation = atan2(dy, dx) * 180 / .pi
        if rotation > 90 || rotation < -90 {
            rotation += 180
        }
        text(
            label,
            at: (
                (dimensionStart.x + dimensionEnd.x) / 2,
                (dimensionStart.y + dimensionEnd.y) / 2 + 0.04
            ),
            height: 0.09,
            layer: layer,
            rotation: rotation
        )
    }

    private mutating func addEntityHeader(
        layer: String,
        subclass: String
    ) {
        pair(5, nextEntityHandle())
        pair(330, "31")
        pair(100, "AcDbEntity")
        pair(8, layer)
        pair(100, subclass)
    }

    private mutating func nextEntityHandle() -> String {
        defer { nextEntityHandleValue += 1 }
        return String(nextEntityHandleValue, radix: 16).uppercased()
    }

    private func stringChunks(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> [String] {
        guard !value.isEmpty else { return [""] }
        var result: [String] = []
        var current = ""
        var currentBytes = 0

        for character in value {
            let text = String(character)
            let byteCount = text.utf8.count
            if !current.isEmpty,
               currentBytes + byteCount > maximumUTF8Bytes {
                result.append(current)
                current = text
                currentBytes = byteCount
            } else {
                current += text
                currentBytes += byteCount
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(format: "%.6f", value)
    }
}
