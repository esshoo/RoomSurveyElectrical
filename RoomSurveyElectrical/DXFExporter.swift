import Foundation
import simd

extension ProjectExportService {
    static func makeDXF(
        title: String,
        room: ExportRoomRecord,
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        let data = Data(
            DXFPlanBuilder(
                title: title,
                record: room,
                metadata: metadata
            ).build().utf8
        )
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-2D",
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
                format: "%02d-%@-2D.dxf",
                index + 1,
                sanitized(room.scan.name)
            )
            archive.add(
                name: name,
                data: Data(
                    DXFPlanBuilder(
                        title: room.scan.name,
                        record: room,
                        metadata: metadata
                    ).build().utf8
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
        let data = Data(
            DXFPlanBuilder.combined(
                title: title,
                rooms: rooms,
                metadata: metadata
            ).utf8
        )
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-Combined-2D",
            extension: "dxf"
        )
    }

    static func makeLayoutDXF(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        let data = Data(
            DXFPlanBuilder.layouts(
                title: title,
                rooms: rooms,
                metadata: metadata
            ).utf8
        )
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-Layouts-2D",
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

    private struct LayoutDescriptor {
        let placement: Placement
        let name: String
        let blockName: String
        let blockRecordHandle: String
        let layoutHandle: String
        let blockBeginHandle: String
        let blockEndHandle: String
        let defaultViewportHandle: String
        let mainViewportHandle: String
        let viewCenter: (x: Double, y: Double)
        let viewHeight: Double
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
        guard let firstRoom = rooms.first else {
            return ""
        }
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
            maximumHeight = max(
                maximumHeight,
                roomBounds.height
            )
        }

        let drawingMaximumX = max(cursorX - spacing, 0.5)
        let drawingMaximumY = max(maximumHeight, 0.5)
        let firstBuilder = DXFPlanBuilder(
            title: title,
            record: firstRoom,
            metadata: metadata
        )
        var dxf = DXFWriter()
        firstBuilder.addHeader(
            to: &dxf,
            bounds: Bounds(
                minimumX: -1,
                maximumX: drawingMaximumX + 1,
                minimumY: -1,
                maximumY: drawingMaximumY + 2
            )
        )
        firstBuilder.addTables(to: &dxf)
        dxf.pair(0, "SECTION")
        dxf.pair(2, "ENTITIES")

        for placement in placements {
            let builder = DXFPlanBuilder(
                title: placement.room.scan.name,
                record: placement.room,
                metadata: metadata,
                translation: placement.translation
            )
            builder.addEntities(to: &dxf)
            let labelX = placement.bounds.minimumX
                + placement.translation.x
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
        dxf.pair(0, "ENDSEC")
        dxf.pair(0, "EOF")
        return dxf.output
    }

    static func layouts(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata
    ) -> String {
        guard let firstRoom = rooms.first else {
            return ""
        }
        let descriptors = layoutDescriptors(for: rooms)
        let maximumX = descriptors.map {
            $0.placement.bounds.maximumX
                + $0.placement.translation.x
        }.max() ?? 1
        let maximumY = descriptors.map {
            $0.placement.bounds.maximumY
                + $0.placement.translation.y
        }.max() ?? 1
        let documentBuilder = DXFPlanBuilder(
            title: title,
            record: firstRoom,
            metadata: metadata
        )
        var dxf = DXFWriter()
        documentBuilder.addLayoutHeader(
            to: &dxf,
            maximumX: maximumX,
            maximumY: maximumY
        )
        documentBuilder.addLayoutClasses(to: &dxf)
        documentBuilder.addLayoutTables(
            to: &dxf,
            descriptors: descriptors
        )
        documentBuilder.addLayoutBlocks(
            to: &dxf,
            descriptors: descriptors
        )
        documentBuilder.addLayoutModelEntities(
            to: &dxf,
            descriptors: descriptors,
            maximumX: maximumX,
            maximumY: maximumY
        )
        documentBuilder.addLayoutObjects(
            to: &dxf,
            descriptors: descriptors
        )
        dxf.pair(0, "EOF")
        return dxf.output
    }

    private static func layoutDescriptors(
        for rooms: [ExportRoomRecord]
    ) -> [LayoutDescriptor] {
        let names = uniqueLayoutNames(for: rooms)
        let spacing = 2.0
        let viewportAspect = 390.0 / 235.0
        var cursorX = 0.0
        return rooms.enumerated().map { index, room in
            let roomBounds = bounds(for: room.project)
            let roomTranslation = (
                x: cursorX - roomBounds.minimumX,
                y: -roomBounds.minimumY
            )
            let placement = Placement(
                room: room,
                bounds: roomBounds,
                translation: roomTranslation
            )
            cursorX += roomBounds.width + spacing

            let displayedMinimumX = roomBounds.minimumX
                + roomTranslation.x
            let displayedMaximumX = roomBounds.maximumX
                + roomTranslation.x
            let displayedMinimumY = roomBounds.minimumY
                + roomTranslation.y
            let displayedMaximumY = roomBounds.maximumY
                + roomTranslation.y
            let paddedWidth = max(
                displayedMaximumX - displayedMinimumX + 0.8,
                0.8
            )
            let paddedHeight = max(
                displayedMaximumY - displayedMinimumY + 0.8,
                0.8
            )
            let requiredViewHeight = max(
                paddedHeight,
                paddedWidth / viewportAspect
            ) * 1.08
            let handleBase = 0x20 + index * 6
            return LayoutDescriptor(
                placement: placement,
                name: names[index],
                blockName: index == 0
                    ? "*Paper_Space"
                    : "*Paper_Space\(index - 1)",
                blockRecordHandle: hexHandle(handleBase),
                layoutHandle: hexHandle(handleBase + 1),
                blockBeginHandle: hexHandle(handleBase + 2),
                blockEndHandle: hexHandle(handleBase + 3),
                defaultViewportHandle: hexHandle(handleBase + 4),
                mainViewportHandle: hexHandle(handleBase + 5),
                viewCenter: (
                    (displayedMinimumX + displayedMaximumX) / 2,
                    (displayedMinimumY + displayedMaximumY) / 2
                ),
                viewHeight: requiredViewHeight
            )
        }
    }

    private static func uniqueLayoutNames(
        for rooms: [ExportRoomRecord]
    ) -> [String] {
        var used: Set<String> = ["model"]
        return rooms.enumerated().map { index, room in
            var base = room.scan.name
                .components(
                    separatedBy: CharacterSet(
                        charactersIn: "<>/\\\":;?*|,="
                    )
                )
                .joined(separator: "-")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            if base.isEmpty {
                base = "Layout \(index + 1)"
            }
            base = String(base.prefix(80))
            var candidate = base
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                let suffixText = " (\(suffix))"
                candidate = String(
                    base.prefix(max(1, 80 - suffixText.count))
                ) + suffixText
                suffix += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    private static func hexHandle(_ value: Int) -> String {
        String(value, radix: 16).uppercased()
    }

    private func addLayoutHeader(
        to dxf: inout DXFWriter,
        maximumX: Double,
        maximumY: Double
    ) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "HEADER")
        dxf.pair(9, "$ACADVER")
        dxf.pair(1, "AC1027")
        dxf.pair(9, "$HANDSEED")
        dxf.pair(5, "FFFFFF")
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
        dxf.pair(10, -1.0)
        dxf.pair(20, -1.0)
        dxf.pair(30, 0.0)
        dxf.pair(9, "$EXTMAX")
        dxf.pair(10, maximumX + 1)
        dxf.pair(20, maximumY + 2)
        dxf.pair(30, 0.0)
        dxf.pair(0, "ENDSEC")
    }

    private func addLayoutClasses(to dxf: inout DXFWriter) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "CLASSES")
        dxf.pair(0, "CLASS")
        dxf.pair(1, "LAYOUT")
        dxf.pair(2, "AcDbLayout")
        dxf.pair(3, "ObjectDBX Classes")
        dxf.pair(90, 0)
        dxf.pair(91, 0)
        dxf.pair(280, 0)
        dxf.pair(281, 0)
        dxf.pair(0, "ENDSEC")
    }

    private func addLayoutTables(
        to dxf: inout DXFWriter,
        descriptors: [LayoutDescriptor]
    ) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "TABLES")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "LTYPE")
        dxf.pair(5, "8")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, 1)
        dxf.pair(0, "LTYPE")
        dxf.pair(5, "9")
        dxf.pair(330, "8")
        dxf.pair(100, "AcDbSymbolTableRecord")
        dxf.pair(100, "AcDbLinetypeTableRecord")
        dxf.pair(2, "CONTINUOUS")
        dxf.pair(70, 0)
        dxf.pair(3, "Solid line")
        dxf.pair(72, 65)
        dxf.pair(73, 0)
        dxf.pair(40, 0.0)
        dxf.pair(0, "ENDTAB")

        let layoutLayers = [
            (name: "0", color: 7, lineWeight: 15)
        ] + layers
        dxf.pair(0, "TABLE")
        dxf.pair(2, "LAYER")
        dxf.pair(5, "A")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, layoutLayers.count)
        for (index, layer) in layoutLayers.enumerated() {
            dxf.pair(0, "LAYER")
            dxf.pair(5, Self.hexHandle(0xB + index))
            dxf.pair(330, "A")
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
        dxf.pair(5, "18")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, 1)
        dxf.pair(0, "STYLE")
        dxf.pair(5, "19")
        dxf.pair(330, "18")
        dxf.pair(100, "AcDbSymbolTableRecord")
        dxf.pair(100, "AcDbTextStyleTableRecord")
        dxf.pair(2, "STANDARD")
        dxf.pair(70, 0)
        dxf.pair(40, 0.0)
        dxf.pair(41, 1.0)
        dxf.pair(50, 0.0)
        dxf.pair(71, 0)
        dxf.pair(42, 0.2)
        dxf.pair(3, "Arial.ttf")
        dxf.pair(4, "")
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "BLOCK_RECORD")
        dxf.pair(5, "3")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbSymbolTable")
        dxf.pair(70, descriptors.count + 1)
        addLayoutBlockRecord(
            to: &dxf,
            handle: "4",
            name: "*Model_Space",
            layoutHandle: "5"
        )
        for descriptor in descriptors {
            addLayoutBlockRecord(
                to: &dxf,
                handle: descriptor.blockRecordHandle,
                name: descriptor.blockName,
                layoutHandle: descriptor.layoutHandle
            )
        }
        dxf.pair(0, "ENDTAB")
        dxf.pair(0, "ENDSEC")
    }

    private func addLayoutBlockRecord(
        to dxf: inout DXFWriter,
        handle: String,
        name: String,
        layoutHandle: String
    ) {
        dxf.pair(0, "BLOCK_RECORD")
        dxf.pair(5, handle)
        dxf.pair(330, "3")
        dxf.pair(100, "AcDbSymbolTableRecord")
        dxf.pair(100, "AcDbBlockTableRecord")
        dxf.pair(2, name)
        dxf.pair(340, layoutHandle)
        dxf.pair(70, 6)
        dxf.pair(280, 1)
        dxf.pair(281, 0)
    }

    private func addLayoutBlocks(
        to dxf: inout DXFWriter,
        descriptors: [LayoutDescriptor]
    ) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "BLOCKS")
        addLayoutBlockBegin(
            to: &dxf,
            handle: "6",
            owner: "4",
            name: "*Model_Space"
        )
        addLayoutBlockEnd(
            to: &dxf,
            handle: "7",
            owner: "4"
        )

        for descriptor in descriptors {
            addLayoutBlockBegin(
                to: &dxf,
                handle: descriptor.blockBeginHandle,
                owner: descriptor.blockRecordHandle,
                name: descriptor.blockName
            )
            addLayoutViewport(
                to: &dxf,
                handle: descriptor.defaultViewportHandle,
                owner: descriptor.blockRecordHandle,
                identifier: 1,
                center: (210, 148.5),
                size: (462, 326.7),
                viewCenter: (210, 148.5),
                viewHeight: 326.7,
                isDefault: true
            )
            addLayoutViewport(
                to: &dxf,
                handle: descriptor.mainViewportHandle,
                owner: descriptor.blockRecordHandle,
                identifier: 2,
                center: (210, 135),
                size: (390, 235),
                viewCenter: descriptor.viewCenter,
                viewHeight: descriptor.viewHeight,
                isDefault: false
            )

            dxf.setEntityContext(
                ownerHandle: descriptor.blockRecordHandle,
                paperSpace: true
            )
            dxf.text(
                metadata.brandName,
                at: (15, 285),
                height: 5,
                layer: "ANNOTATIONS",
                horizontalAlignment: 0
            )
            dxf.text(
                descriptor.name,
                at: (15, 275),
                height: 4,
                layer: "ANNOTATIONS",
                horizontalAlignment: 0
            )
            if !descriptor.placement.room.location.isEmpty {
                dxf.text(
                    descriptor.placement.room.location,
                    at: (15, 267),
                    height: 2.5,
                    layer: "ANNOTATIONS",
                    horizontalAlignment: 0
                )
            }
            dxf.text(
                metadata.exportLine,
                at: (405, 8),
                height: 2.5,
                layer: "ANNOTATIONS",
                horizontalAlignment: 2
            )
            dxf.setEntityContext(ownerHandle: nil)
            addLayoutBlockEnd(
                to: &dxf,
                handle: descriptor.blockEndHandle,
                owner: descriptor.blockRecordHandle
            )
        }
        dxf.pair(0, "ENDSEC")
    }

    private func addLayoutBlockBegin(
        to dxf: inout DXFWriter,
        handle: String,
        owner: String,
        name: String
    ) {
        dxf.pair(0, "BLOCK")
        dxf.pair(5, handle)
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
    }

    private func addLayoutBlockEnd(
        to dxf: inout DXFWriter,
        handle: String,
        owner: String
    ) {
        dxf.pair(0, "ENDBLK")
        dxf.pair(5, handle)
        dxf.pair(330, owner)
        dxf.pair(100, "AcDbEntity")
        dxf.pair(8, "0")
        dxf.pair(100, "AcDbBlockEnd")
    }

    private func addLayoutViewport(
        to dxf: inout DXFWriter,
        handle: String,
        owner: String,
        identifier: Int,
        center: (x: Double, y: Double),
        size: (width: Double, height: Double),
        viewCenter: (x: Double, y: Double),
        viewHeight: Double,
        isDefault: Bool
    ) {
        dxf.pair(0, "VIEWPORT")
        dxf.pair(5, handle)
        dxf.pair(330, owner)
        dxf.pair(100, "AcDbEntity")
        dxf.pair(67, 1)
        dxf.pair(8, "ANNOTATIONS")
        dxf.pair(100, "AcDbViewport")
        dxf.pair(10, center.x)
        dxf.pair(20, center.y)
        dxf.pair(30, 0.0)
        dxf.pair(40, size.width)
        dxf.pair(41, size.height)
        dxf.pair(68, isDefault ? 1 : 2)
        dxf.pair(69, identifier)
        dxf.pair(12, viewCenter.x)
        dxf.pair(22, viewCenter.y)
        dxf.pair(13, 0.0)
        dxf.pair(23, 0.0)
        dxf.pair(14, 10.0)
        dxf.pair(24, 10.0)
        dxf.pair(15, 10.0)
        dxf.pair(25, 10.0)
        dxf.pair(16, 0.0)
        dxf.pair(26, 0.0)
        dxf.pair(36, 1.0)
        dxf.pair(17, 0.0)
        dxf.pair(27, 0.0)
        dxf.pair(37, 0.0)
        dxf.pair(42, 50.0)
        dxf.pair(43, 0.0)
        dxf.pair(44, 0.0)
        dxf.pair(45, viewHeight)
        dxf.pair(50, 0.0)
        dxf.pair(51, 0.0)
        dxf.pair(72, 100)
        dxf.pair(90, isDefault ? 557088 : 0)
        dxf.pair(1, "")
        dxf.pair(281, 0)
        dxf.pair(71, 0)
        dxf.pair(74, 0)
        dxf.pair(110, 0.0)
        dxf.pair(120, 0.0)
        dxf.pair(130, 0.0)
        dxf.pair(111, 1.0)
        dxf.pair(121, 0.0)
        dxf.pair(131, 0.0)
        dxf.pair(112, 0.0)
        dxf.pair(122, 1.0)
        dxf.pair(132, 0.0)
        dxf.pair(79, 0)
        dxf.pair(146, 0.0)
        dxf.pair(282, 0)
    }

    private func addLayoutModelEntities(
        to dxf: inout DXFWriter,
        descriptors: [LayoutDescriptor],
        maximumX: Double,
        maximumY: Double
    ) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "ENTITIES")
        dxf.setEntityContext(ownerHandle: "4")

        for descriptor in descriptors {
            let placement = descriptor.placement
            let builder = DXFPlanBuilder(
                title: placement.room.scan.name,
                record: placement.room,
                metadata: metadata,
                translation: placement.translation
            )
            builder.addEntities(to: &dxf)
            let labelX = placement.bounds.minimumX
                + placement.translation.x
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
            at: (0, maximumY + 1.42),
            height: 0.22,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            metadata.projectLine,
            at: (0, maximumY + 1.15),
            height: 0.09,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            title,
            at: (0, maximumY + 0.92),
            height: 0.14,
            layer: "ANNOTATIONS",
            horizontalAlignment: 0
        )
        dxf.text(
            metadata.exportLine,
            at: (maximumX, -0.55),
            height: 0.08,
            layer: "ANNOTATIONS",
            horizontalAlignment: 2
        )
        dxf.setEntityContext(ownerHandle: nil)
        dxf.pair(0, "ENDSEC")
    }

    private func addLayoutObjects(
        to dxf: inout DXFWriter,
        descriptors: [LayoutDescriptor]
    ) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "OBJECTS")
        dxf.pair(0, "DICTIONARY")
        dxf.pair(5, "1")
        dxf.pair(330, "0")
        dxf.pair(100, "AcDbDictionary")
        dxf.pair(281, 1)
        dxf.pair(3, "ACAD_LAYOUT")
        dxf.pair(350, "2")

        dxf.pair(0, "DICTIONARY")
        dxf.pair(5, "2")
        dxf.pair(330, "1")
        dxf.pair(100, "AcDbDictionary")
        dxf.pair(281, 1)
        dxf.pair(3, "Model")
        dxf.pair(350, "5")
        for descriptor in descriptors {
            dxf.pair(3, descriptor.name)
            dxf.pair(350, descriptor.layoutHandle)
        }

        addLayoutObject(
            to: &dxf,
            handle: "5",
            blockRecordHandle: "4",
            name: "Model",
            tabOrder: 0,
            defaultViewportHandle: nil,
            isModel: true
        )
        for (index, descriptor) in descriptors.enumerated() {
            addLayoutObject(
                to: &dxf,
                handle: descriptor.layoutHandle,
                blockRecordHandle: descriptor.blockRecordHandle,
                name: descriptor.name,
                tabOrder: index + 1,
                defaultViewportHandle:
                    descriptor.defaultViewportHandle,
                isModel: false
            )
        }
        dxf.pair(0, "ENDSEC")
    }

    private func addLayoutObject(
        to dxf: inout DXFWriter,
        handle: String,
        blockRecordHandle: String,
        name: String,
        tabOrder: Int,
        defaultViewportHandle: String?,
        isModel: Bool
    ) {
        dxf.pair(0, "LAYOUT")
        dxf.pair(5, handle)
        dxf.pair(330, "2")
        dxf.pair(100, "AcDbPlotSettings")
        dxf.pair(1, "")
        dxf.pair(2, "")
        dxf.pair(4, "A3")
        dxf.pair(6, "")
        dxf.pair(40, 7.5)
        dxf.pair(41, 20.0)
        dxf.pair(42, 7.5)
        dxf.pair(43, 20.0)
        dxf.pair(44, 420.0)
        dxf.pair(45, 297.0)
        dxf.pair(46, 0.0)
        dxf.pair(47, 0.0)
        dxf.pair(48, 0.0)
        dxf.pair(49, 0.0)
        dxf.pair(140, 0.0)
        dxf.pair(141, 0.0)
        dxf.pair(142, 1.0)
        dxf.pair(143, 1.0)
        dxf.pair(70, isModel ? 1024 : 0)
        dxf.pair(72, 1)
        dxf.pair(73, 0)
        dxf.pair(74, 5)
        dxf.pair(7, "")
        dxf.pair(75, 16)
        dxf.pair(76, 0)
        dxf.pair(77, 2)
        dxf.pair(78, 300)
        dxf.pair(147, 1.0)
        dxf.pair(148, 0.0)
        dxf.pair(149, 0.0)

        dxf.pair(100, "AcDbLayout")
        dxf.pair(1, name)
        dxf.pair(70, 1)
        dxf.pair(71, tabOrder)
        dxf.pair(10, 0.0)
        dxf.pair(20, 0.0)
        dxf.pair(11, 420.0)
        dxf.pair(21, 297.0)
        dxf.pair(12, 0.0)
        dxf.pair(22, 0.0)
        dxf.pair(32, 0.0)
        dxf.pair(14, 1e20)
        dxf.pair(24, 1e20)
        dxf.pair(34, 1e20)
        dxf.pair(15, -1e20)
        dxf.pair(25, -1e20)
        dxf.pair(35, -1e20)
        dxf.pair(146, 0.0)
        dxf.pair(13, 0.0)
        dxf.pair(23, 0.0)
        dxf.pair(33, 0.0)
        dxf.pair(16, 1.0)
        dxf.pair(26, 0.0)
        dxf.pair(36, 0.0)
        dxf.pair(17, 0.0)
        dxf.pair(27, 1.0)
        dxf.pair(37, 0.0)
        dxf.pair(76, 1)
        dxf.pair(330, blockRecordHandle)
        if let defaultViewportHandle {
            dxf.pair(331, defaultViewportHandle)
        }
    }

    func build() -> String {
        var dxf = DXFWriter()
        addHeader(to: &dxf)
        addTables(to: &dxf)
        dxf.pair(0, "SECTION")
        dxf.pair(2, "ENTITIES")
        addEntities(to: &dxf)
        addDrawingInformation(to: &dxf)
        dxf.pair(0, "ENDSEC")
        dxf.pair(0, "EOF")
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
                minimumX: drawingBounds.minimumX
                    + translation.x,
                maximumX: drawingBounds.maximumX
                    + translation.x,
                minimumY: drawingBounds.minimumY
                    + translation.y,
                maximumY: drawingBounds.maximumY
                    + translation.y
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
        dxf.pair(1, "AC1027")
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

    private static func bounds(for project: RoomProject) -> Bounds {
        let points = ExportGeometry.allPlanPoints(in: project)
            .compactMap { point -> (x: Double, y: Double)? in
                let x = Double(point.x)
                let y = Double(-point.y)
                guard x.isFinite, y.isFinite else {
                    return nil
                }
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
            minimumX: points.dropFirst().reduce(first.x) {
                min($0, $1.x)
            },
            maximumX: points.dropFirst().reduce(first.x) {
                max($0, $1.x)
            },
            minimumY: points.dropFirst().reduce(first.y) {
                min($0, $1.y)
            },
            maximumY: points.dropFirst().reduce(first.y) {
                max($0, $1.y)
            }
        )
    }

    private func addTables(to dxf: inout DXFWriter) {
        dxf.pair(0, "SECTION")
        dxf.pair(2, "TABLES")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "LTYPE")
        dxf.pair(70, 1)
        dxf.pair(0, "LTYPE")
        dxf.pair(2, "CONTINUOUS")
        dxf.pair(70, 0)
        dxf.pair(3, "Solid line")
        dxf.pair(72, 65)
        dxf.pair(73, 0)
        dxf.pair(40, 0.0)
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "LAYER")
        dxf.pair(70, layers.count)
        for layer in layers {
            dxf.pair(0, "LAYER")
            dxf.pair(2, layer.name)
            dxf.pair(70, 0)
            dxf.pair(62, layer.color)
            dxf.pair(6, "CONTINUOUS")
            dxf.pair(370, layer.lineWeight)
        }
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "TABLE")
        dxf.pair(2, "STYLE")
        dxf.pair(70, 1)
        dxf.pair(0, "STYLE")
        dxf.pair(2, "STANDARD")
        dxf.pair(70, 0)
        dxf.pair(40, 0.0)
        dxf.pair(41, 1.0)
        dxf.pair(50, 0.0)
        dxf.pair(71, 0)
        dxf.pair(42, 0.2)
        dxf.pair(3, "Arial.ttf")
        dxf.pair(4, "")
        dxf.pair(0, "ENDTAB")

        dxf.pair(0, "ENDSEC")
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
    private var entityOwnerHandle: String?
    private var paperSpaceEntity = false
    private var nextEntityHandleValue = 0x100000

    mutating func setEntityContext(
        ownerHandle: String?,
        paperSpace: Bool = false
    ) {
        entityOwnerHandle = ownerHandle
        paperSpaceEntity = ownerHandle == nil ? false : paperSpace
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
        if entityOwnerHandle == nil {
            pair(8, layer)
        } else {
            addContextualEntityHeader(
                layer: layer,
                subclass: "AcDbLine"
            )
        }
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
        if entityOwnerHandle == nil {
            pair(100, "AcDbEntity")
            pair(8, layer)
            pair(100, "AcDbPolyline")
        } else {
            addContextualEntityHeader(
                layer: layer,
                subclass: "AcDbPolyline"
            )
        }
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
        if entityOwnerHandle == nil {
            pair(8, layer)
        } else {
            addContextualEntityHeader(
                layer: layer,
                subclass: "AcDbCircle"
            )
        }
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
        pair(0, "TEXT")
        if entityOwnerHandle == nil {
            pair(8, layer)
        } else {
            addContextualEntityHeader(
                layer: layer,
                subclass: "AcDbText"
            )
        }
        pair(10, point.x)
        pair(20, point.y)
        pair(30, 0.0)
        pair(40, height)
        pair(1, value)
        pair(50, rotation)
        pair(7, "STANDARD")
        pair(72, horizontalAlignment)
        pair(73, 2)
        pair(11, point.x)
        pair(21, point.y)
        pair(31, 0.0)
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
        line(
            from: dimensionStart,
            to: dimensionEnd,
            layer: layer
        )

        let tickLength = 0.045
        let tangent = (x: dx / length, y: dy / length)
        let tick = (
            x: (tangent.x + perpendicular.x / max(offset, 0.001))
                * tickLength,
            y: (tangent.y + perpendicular.y / max(offset, 0.001))
                * tickLength
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

    private mutating func addContextualEntityHeader(
        layer: String,
        subclass: String
    ) {
        guard let entityOwnerHandle else { return }
        pair(5, nextEntityHandle())
        pair(330, entityOwnerHandle)
        pair(100, "AcDbEntity")
        if paperSpaceEntity {
            pair(67, 1)
        }
        pair(8, layer)
        pair(100, subclass)
    }

    private mutating func nextEntityHandle() -> String {
        defer { nextEntityHandleValue += 1 }
        return String(
            nextEntityHandleValue,
            radix: 16
        ).uppercased()
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        return String(format: "%.6f", value)
    }
}
