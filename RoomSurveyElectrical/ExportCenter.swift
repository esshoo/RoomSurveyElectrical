import Foundation
import simd
import SwiftUI
import UIKit

struct ExportRoomRecord: Identifiable {
    let scan: ScanReference
    let location: String
    let project: RoomProject
    let summary: RoomTakeoffSummary

    var id: UUID { scan.id }
}

enum ExportScopeBuilder {
    static func records(
        in surveyProject: SurveyProject,
        scopeItemID: UUID?,
        includedOnly: Bool
    ) -> [ExportRoomRecord] {
        let allowedParentIDs: Set<UUID>?
        if let scopeItemID {
            allowedParentIDs = surveyProject
                .descendantIDs(of: scopeItemID)
                .union([scopeItemID])
        } else {
            allowedParentIDs = nil
        }

        return surveyProject.scans
            .filter { scan in
                guard !scan.archived else { return false }
                guard !hasArchivedAncestor(
                    scan.parentID,
                    in: surveyProject
                ) else {
                    return false
                }
                if includedOnly && !scan.includedInTakeoff {
                    return false
                }
                guard let allowedParentIDs else { return true }
                return scan.parentID.map(allowedParentIDs.contains) == true
            }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { scan in
                guard let roomProject = ProjectRepository.load(
                    projectID: scan.id
                ) else {
                    return nil
                }
                return ExportRoomRecord(
                    scan: scan,
                    location: locationPath(
                        for: scan.parentID,
                        in: surveyProject
                    ),
                    project: roomProject,
                    summary: RoomTakeoffSummary(project: roomProject)
                )
            }
    }

    private static func hasArchivedAncestor(
        _ itemID: UUID?,
        in project: SurveyProject
    ) -> Bool {
        var currentID = itemID
        var visited: Set<UUID> = []
        while let id = currentID,
              !visited.contains(id),
              let item = project.item(id: id) {
            if item.archived {
                return true
            }
            visited.insert(id)
            currentID = item.parentID
        }
        return false
    }

    private static func locationPath(
        for itemID: UUID?,
        in project: SurveyProject
    ) -> String {
        var names: [String] = []
        var currentID = itemID
        var visited: Set<UUID> = []
        while let id = currentID,
              !visited.contains(id),
              let item = project.item(id: id) {
            visited.insert(id)
            names.append(item.name)
            currentID = item.parentID
        }
        return names.reversed().joined(separator: " ← ")
    }
}

struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ExportShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct ExportCenterView: View {
    let surveyProject: SurveyProject
    let scopeItemID: UUID?
    let title: String

    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false
    @State private var errorMessage: String?

    private var takeoffRooms: [ExportRoomRecord] {
        ExportScopeBuilder.records(
            in: surveyProject,
            scopeItemID: scopeItemID,
            includedOnly: true
        )
    }

    private var planRooms: [ExportRoomRecord] {
        ExportScopeBuilder.records(
            in: surveyProject,
            scopeItemID: scopeItemID,
            includedOnly: false
        )
    }

    var body: some View {
        List {
            Section("تقرير الحصر") {
                exportButton(
                    "تصدير الحصر XLSX",
                    subtitle: "ملخص وغرف وأرضيات وحوائط وفتحات وكهرباء",
                    systemImage: "tablecells.fill",
                    disabled: takeoffRooms.isEmpty
                ) {
                    try ProjectExportService.makeTakeoffXLSX(
                        title: title,
                        rooms: takeoffRooms
                    )
                }

                exportButton(
                    "تصدير تقرير الحصر PDF",
                    subtitle: "تقرير عربي للطباعة بالمجاميع والتفاصيل",
                    systemImage: "doc.richtext.fill",
                    disabled: takeoffRooms.isEmpty
                ) {
                    try ProjectExportService.makeTakeoffPDF(
                        title: title,
                        rooms: takeoffRooms
                    )
                }
            }

            Section("مخططات 2D PDF") {
                exportButton(
                    "كل المخططات - كامل الطبقات",
                    subtitle: "صفحة مستقلة لكل مسح داخل ملف PDF واحد",
                    systemImage: "square.3.layers.3d.top.filled",
                    disabled: planRooms.isEmpty
                ) {
                    try ProjectExportService.makePlanPDF(
                        title: title,
                        rooms: planRooms
                    )
                }

                ForEach(planRooms) { room in
                    exportButton(
                        room.scan.name,
                        subtitle: room.location.isEmpty
                            ? "مخطط كامل الطبقات"
                            : "\(room.location) • كامل الطبقات",
                        systemImage: "doc.text.image"
                    ) {
                        try ProjectExportService.makePlanPDF(
                            title: room.scan.name,
                            rooms: [room]
                        )
                    }
                }
            }

            Section("محتوى مخطط 2D") {
                Label(
                    "الأرضيات والحوائط والأبواب والشبابيك والفرش",
                    systemImage: "square.grid.2x2.fill"
                )
                Label(
                    "الكهرباء وإضاءة السقف وأبعاد الحوائط والكهرباء",
                    systemImage: "bolt.badge.clock.fill"
                )
                Label(
                    "الرسم متجه ومناسب للتكبير والطباعة على A3",
                    systemImage: "printer.fill"
                )
            }
        }
        .navigationTitle("تصدير \(title)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("جاري إنشاء الملف...")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(
                            cornerRadius: 14
                        ))
                }
            }
        }
        .sheet(item: $exportedFile) { file in
            ExportShareSheet(items: [file.url])
        }
        .alert(
            "تعذر إنشاء الملف",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportButton(
        _ label: String,
        subtitle: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () throws -> URL
    ) -> some View {
        Button {
            performExport(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isExporting)
    }

    private func performExport(_ action: @escaping () throws -> URL) {
        isExporting = true
        Task { @MainActor in
            await Task.yield()
            defer { isExporting = false }
            do {
                exportedFile = ExportedFile(url: try action())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum ProjectExportError: LocalizedError {
    case noRooms
    case cannotCreateFile

    var errorDescription: String? {
        switch self {
        case .noRooms:
            "لا توجد مسحات صالحة للتصدير في هذا النطاق."
        case .cannotCreateFile:
            "تعذر إنشاء ملف التصدير."
        }
    }
}

enum ProjectExportService {
    static func makeTakeoffXLSX(
        title: String,
        rooms: [ExportRoomRecord]
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        let workbook = TakeoffXLSXBuilder(title: title, rooms: rooms)
        let data = try workbook.build()
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-takeoff",
            extension: "xlsx"
        )
    }

    static func makeTakeoffPDF(
        title: String,
        rooms: [ExportRoomRecord]
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        let url = temporaryURL(
            name: "\(sanitized(title))-takeoff-report",
            extension: "pdf"
        )
        try TakeoffPDFRenderer.render(
            title: title,
            rooms: rooms,
            to: url
        )
        return url
    }

    static func makePlanPDF(
        title: String,
        rooms: [ExportRoomRecord]
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        let url = temporaryURL(
            name: "\(sanitized(title))-2D-full-layers",
            extension: "pdf"
        )
        try PlanPDFRenderer.render(
            title: title,
            rooms: rooms,
            to: url
        )
        return url
    }

    private static func writeTemporaryFile(
        _ data: Data,
        name: String,
        extension fileExtension: String
    ) throws -> URL {
        let url = temporaryURL(name: name, extension: fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ProjectExportError.cannotCreateFile
        }
    }

    private static func temporaryURL(
        name: String,
        extension fileExtension: String
    ) -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("3ERoomElectrical-Exports", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
            .appendingPathComponent(name)
            .appendingPathExtension(fileExtension)
    }

    private static func sanitized(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? "3ERoomElectrical" : trimmed
    }
}

private enum XLSXCellValue {
    case text(String)
    case number(Double)
    case formula(String, Double)
}

private struct XLSXCell {
    let value: XLSXCellValue
    let style: Int

    static func text(_ value: String, style: Int = 4) -> XLSXCell {
        XLSXCell(value: .text(value), style: style)
    }

    static func number(_ value: Double, style: Int = 3) -> XLSXCell {
        XLSXCell(value: .number(value), style: style)
    }

    static func integer(_ value: Int, style: Int = 3) -> XLSXCell {
        XLSXCell(value: .number(Double(value)), style: style)
    }

    static func formula(
        _ formula: String,
        cachedValue: Double,
        style: Int = 3
    ) -> XLSXCell {
        XLSXCell(
            value: .formula(formula, cachedValue),
            style: style
        )
    }
}

private struct XLSXSheet {
    let name: String
    let rows: [[XLSXCell]]
    let columnWidths: [Double]
    let mergedTitle: Bool
    let autoFilterRow: Int?
}

private struct TakeoffXLSXBuilder {
    let title: String
    let rooms: [ExportRoomRecord]

    func build() throws -> Data {
        let sheets = makeSheets()
        var archive = StoredZIPArchive()

        archive.add(
            name: "[Content_Types].xml",
            text: contentTypesXML(sheetCount: sheets.count)
        )
        archive.add(name: "_rels/.rels", text: rootRelationshipsXML)
        archive.add(name: "docProps/app.xml", text: appPropertiesXML)
        archive.add(
            name: "docProps/core.xml",
            text: corePropertiesXML
        )
        archive.add(
            name: "xl/workbook.xml",
            text: workbookXML(sheets: sheets)
        )
        archive.add(
            name: "xl/_rels/workbook.xml.rels",
            text: workbookRelationshipsXML(sheetCount: sheets.count)
        )
        archive.add(name: "xl/styles.xml", text: workbookStylesXML)

        for (index, sheet) in sheets.enumerated() {
            archive.add(
                name: "xl/worksheets/sheet\(index + 1).xml",
                text: worksheetXML(sheet)
            )
        }
        return archive.data()
    }

    private func makeSheets() -> [XLSXSheet] {
        [
            summarySheet(),
            roomsSheet(),
            floorsSheet(),
            wallsSheet(),
            openingsSheet(),
            electricalSheet()
        ]
    }

    private func summarySheet() -> XLSXSheet {
        let total = ProjectTakeoffSummary(
            rooms: rooms.map(\.summary)
        )
        let lastRoomRow = max(3, rooms.count + 2)
        let roomsRange = "'الغرف'!"

        let rows: [[XLSXCell]] = [
            [.text("تقرير حصر – \(title)", style: 1)],
            [
                .text("البند", style: 2),
                .text("القيمة", style: 2),
                .text("الوحدة", style: 2)
            ],
            [
                .text("عدد المسحات"),
                .formula(
                    "COUNTA(\(roomsRange)B3:B\(lastRoomRow))",
                    cachedValue: Double(rooms.count),
                    style: 5
                ),
                .text("مسح", style: 5)
            ],
            [
                .text("إجمالي الأرضيات"),
                .formula(
                    "SUM(\(roomsRange)C3:C\(lastRoomRow))",
                    cachedValue: Double(total.floorArea),
                    style: 5
                ),
                .text("م²", style: 5)
            ],
            [
                .text("إجمالي الأسقف"),
                .formula(
                    "SUM(\(roomsRange)D3:D\(lastRoomRow))",
                    cachedValue: Double(total.ceilingArea),
                    style: 5
                ),
                .text("م²", style: 5)
            ],
            [
                .text("مساحة الحوائط الإجمالية"),
                .formula(
                    "SUM(\(roomsRange)E3:E\(lastRoomRow))",
                    cachedValue: Double(total.grossWallArea),
                    style: 5
                ),
                .text("م²", style: 5)
            ],
            [
                .text("مساحة الفتحات المخصومة"),
                .formula(
                    "SUM(\(roomsRange)F3:F\(lastRoomRow))",
                    cachedValue: Double(total.deductedOpeningArea),
                    style: 5
                ),
                .text("م²", style: 5)
            ],
            [
                .text("صافي مساحة الحوائط"),
                .formula(
                    "SUM(\(roomsRange)G3:G\(lastRoomRow))",
                    cachedValue: Double(total.netWallArea),
                    style: 5
                ),
                .text("م²", style: 5)
            ],
            [
                .text("الأبواب"),
                .formula(
                    "SUM(\(roomsRange)H3:H\(lastRoomRow))",
                    cachedValue: Double(total.doorCount),
                    style: 5
                ),
                .text("عدد", style: 5)
            ],
            [
                .text("الشبابيك"),
                .formula(
                    "SUM(\(roomsRange)I3:I\(lastRoomRow))",
                    cachedValue: Double(total.windowCount),
                    style: 5
                ),
                .text("عدد", style: 5)
            ],
            [
                .text("الفتحات المعمارية"),
                .formula(
                    "SUM(\(roomsRange)J3:J\(lastRoomRow))",
                    cachedValue: Double(total.architecturalOpeningCount),
                    style: 5
                ),
                .text("عدد", style: 5)
            ],
            [
                .text("نقاط الكهرباء"),
                .formula(
                    "SUM(\(roomsRange)K3:K\(lastRoomRow))",
                    cachedValue: Double(total.electricalPointCount),
                    style: 5
                ),
                .text("نقطة", style: 5)
            ],
            [
                .text("إضاءة السقف"),
                .formula(
                    "SUM(\(roomsRange)L3:L\(lastRoomRow))",
                    cachedValue: Double(total.ceilingLightCount),
                    style: 5
                ),
                .text("وحدة", style: 5)
            ]
        ]
        return XLSXSheet(
            name: "الملخص",
            rows: rows,
            columnWidths: [34, 18, 14],
            mergedTitle: true,
            autoFilterRow: nil
        )
    }

    private func roomsSheet() -> XLSXSheet {
        var rows: [[XLSXCell]] = [
            [.text("ملخص المسحات – \(title)", style: 1)],
            [
                "الموقع",
                "اسم المسح",
                "الأرضيات م²",
                "الأسقف م²",
                "الحوائط إجمالي م²",
                "خصم الفتحات م²",
                "صافي الحوائط م²",
                "أبواب",
                "شبابيك",
                "فتحات",
                "نقاط كهرباء",
                "إضاءة سقف"
            ].map { .text($0, style: 2) }
        ]

        for room in rooms {
            let summary = room.summary
            rows.append([
                .text(room.location),
                .text(room.scan.name),
                .number(Double(summary.floorArea)),
                .number(Double(summary.ceilingArea)),
                .number(Double(summary.grossWallArea)),
                .number(Double(summary.deductedOpeningArea)),
                .number(Double(summary.netWallArea)),
                .integer(summary.doorCount),
                .integer(summary.windowCount),
                .integer(summary.architecturalOpeningCount),
                .integer(summary.electricalPointCount),
                .integer(summary.ceilingLightCount)
            ])
        }

        return XLSXSheet(
            name: "الغرف",
            rows: rows,
            columnWidths: [28, 28, 16, 16, 21, 19, 20, 11, 11, 11, 17, 16],
            mergedTitle: true,
            autoFilterRow: 2
        )
    }

    private func floorsSheet() -> XLSXSheet {
        var rows: [[XLSXCell]] = [
            [.text("تفاصيل الأرضيات – \(title)", style: 1)],
            [
                "الموقع",
                "اسم المسح",
                "رقم السطح",
                "الطول م",
                "العرض م",
                "المساحة م²"
            ].map { .text($0, style: 2) }
        ]

        for room in rooms {
            for (index, floor) in room.summary.floors.enumerated() {
                let row = rows.count + 1
                rows.append([
                    .text(room.location),
                    .text(room.scan.name),
                    .integer(index + 1),
                    .number(Double(floor.width)),
                    .number(Double(floor.depth)),
                    .formula(
                        "D\(row)*E\(row)",
                        cachedValue: Double(floor.area)
                    )
                ])
            }
        }
        return XLSXSheet(
            name: "الأرضيات",
            rows: rows,
            columnWidths: [28, 28, 14, 14, 14, 17],
            mergedTitle: true,
            autoFilterRow: 2
        )
    }

    private func wallsSheet() -> XLSXSheet {
        var rows: [[XLSXCell]] = [
            [.text("تفاصيل الحوائط – \(title)", style: 1)],
            [
                "الموقع",
                "اسم المسح",
                "رقم الحائط",
                "الطول م",
                "الارتفاع م",
                "الإجمالي م²",
                "عدد الفتحات",
                "خصم الفتحات م²",
                "الصافي م²"
            ].map { .text($0, style: 2) }
        ]

        for room in rooms {
            for (index, wall) in room.summary.walls.enumerated() {
                let row = rows.count + 1
                rows.append([
                    .text(room.location),
                    .text(room.scan.name),
                    .integer(index + 1),
                    .number(Double(wall.width)),
                    .number(Double(wall.height)),
                    .formula(
                        "D\(row)*E\(row)",
                        cachedValue: Double(wall.grossArea)
                    ),
                    .integer(wall.openingCount),
                    .number(Double(wall.deductedOpeningArea)),
                    .formula(
                        "MAX(0,F\(row)-H\(row))",
                        cachedValue: Double(wall.netArea)
                    )
                ])
            }
        }
        return XLSXSheet(
            name: "الحوائط",
            rows: rows,
            columnWidths: [28, 28, 14, 14, 14, 17, 16, 19, 17],
            mergedTitle: true,
            autoFilterRow: 2
        )
    }

    private func openingsSheet() -> XLSXSheet {
        var rows: [[XLSXCell]] = [
            [.text("تفاصيل الأبواب والشبابيك والفتحات – \(title)", style: 1)],
            [
                "الموقع",
                "اسم المسح",
                "النوع",
                "العرض م",
                "الارتفاع م",
                "المساحة م²",
                "مرتبط بحائط"
            ].map { .text($0, style: 2) }
        ]

        for room in rooms {
            for opening in room.summary.openings {
                let row = rows.count + 1
                rows.append([
                    .text(room.location),
                    .text(room.scan.name),
                    .text(opening.title),
                    .number(Double(opening.width)),
                    .number(Double(opening.height)),
                    .formula(
                        "D\(row)*E\(row)",
                        cachedValue: Double(opening.area)
                    ),
                    .text(opening.wallID == nil ? "لا" : "نعم")
                ])
            }
        }
        return XLSXSheet(
            name: "الفتحات",
            rows: rows,
            columnWidths: [28, 28, 18, 14, 14, 17, 17],
            mergedTitle: true,
            autoFilterRow: 2
        )
    }

    private func electricalSheet() -> XLSXSheet {
        var rows: [[XLSXCell]] = [
            [.text("تفاصيل الكهرباء – \(title)", style: 1)],
            [
                "الموقع",
                "اسم المسح",
                "العنصر",
                "الحالة",
                "العدد"
            ].map { .text($0, style: 2) }
        ]

        for room in rooms {
            for line in room.summary.electrical {
                rows.append([
                    .text(room.location),
                    .text(room.scan.name),
                    .text(line.type.title),
                    .text(line.status.title),
                    .integer(line.count)
                ])
            }
            if room.summary.manualCeilingLightCount > 0 {
                rows.append([
                    .text(room.location),
                    .text(room.scan.name),
                    .text("إضاءة سقف – يدوي"),
                    .text("مقترح"),
                    .integer(room.summary.manualCeilingLightCount)
                ])
            }
            if room.summary.automaticCeilingLightCount > 0 {
                rows.append([
                    .text(room.location),
                    .text(room.scan.name),
                    .text("إضاءة سقف – تلقائي"),
                    .text("مقترح"),
                    .integer(room.summary.automaticCeilingLightCount)
                ])
            }
        }
        return XLSXSheet(
            name: "الكهرباء",
            rows: rows,
            columnWidths: [28, 28, 38, 16, 14],
            mergedTitle: true,
            autoFilterRow: 2
        )
    }

    private func worksheetXML(_ sheet: XLSXSheet) -> String {
        let lastColumn = columnName(max(sheet.columnWidths.count, 1))
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetViews><sheetView workbookViewId="0" rightToLeft="1"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="18"/>
        <cols>
        """
        for (index, width) in sheet.columnWidths.enumerated() {
            xml += """
            <col min="\(index + 1)" max="\(index + 1)" width="\(width)" customWidth="1"/>
            """
        }
        xml += "</cols><sheetData>"

        for (rowIndex, row) in sheet.rows.enumerated() {
            xml += "<row r=\"\(rowIndex + 1)\""
            if rowIndex == 0 {
                xml += " ht=\"28\" customHeight=\"1\""
            }
            xml += ">"
            for (columnIndex, cell) in row.enumerated() {
                let reference = "\(columnName(columnIndex + 1))\(rowIndex + 1)"
                switch cell.value {
                case .text(let value):
                    xml += """
                    <c r="\(reference)" s="\(cell.style)" t="inlineStr"><is><t xml:space="preserve">\(xmlEscaped(value))</t></is></c>
                    """
                case .number(let value):
                    xml += """
                    <c r="\(reference)" s="\(cell.style)"><v>\(spreadsheetNumber(value))</v></c>
                    """
                case .formula(let formula, let cached):
                    xml += """
                    <c r="\(reference)" s="\(cell.style)"><f>\(xmlEscaped(formula))</f><v>\(spreadsheetNumber(cached))</v></c>
                    """
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData>"

        if sheet.mergedTitle {
            xml += """
            <mergeCells count="1"><mergeCell ref="A1:\(lastColumn)1"/></mergeCells>
            """
        }
        if let row = sheet.autoFilterRow {
            xml += """
            <autoFilter ref="A\(row):\(lastColumn)\(max(row, sheet.rows.count))"/>
            """
        }
        xml += """
        <pageMargins left="0.25" right="0.25" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>
        <pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>
        </worksheet>
        """
        return xml
    }

    private func workbookXML(sheets: [XLSXSheet]) -> String {
        let sheetNodes = sheets.enumerated().map { index, sheet in
            """
            <sheet name="\(xmlEscaped(sheet.name))" sheetId="\(index + 1)" r:id="rId\(index + 1)"/>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <workbookPr/><bookViews><workbookView/></bookViews>
        <sheets>\(sheetNodes)</sheets>
        <calcPr calcId="191029" fullCalcOnLoad="1" forceFullCalc="1"/>
        </workbook>
        """
    }

    private func workbookRelationshipsXML(sheetCount: Int) -> String {
        var relationships = (1...sheetCount).map { index in
            """
            <Relationship Id="rId\(index)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\(index).xml"/>
            """
        }.joined()
        relationships += """
        <Relationship Id="rId\(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
        """
    }

    private func contentTypesXML(sheetCount: Int) -> String {
        let sheets = (1...sheetCount).map { index in
            """
            <Override PartName="/xl/worksheets/sheet\(index).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        \(sheets)
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private var rootRelationshipsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private var workbookStylesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>
        <fonts count="3">
        <font><sz val="11"/><name val="Arial"/></font>
        <font><b/><sz val="16"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>
        <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>
        </fonts>
        <fills count="4">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF1262A3"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF2387C9"/><bgColor indexed="64"/></patternFill></fill>
        </fills>
        <borders count="2">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><left style="thin"><color rgb="FFD3DAE3"/></left><right style="thin"><color rgb="FFD3DAE3"/></right><top style="thin"><color rgb="FFD3DAE3"/></top><bottom style="thin"><color rgb="FFD3DAE3"/></bottom><diagonal/></border>
        </borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="6">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="2" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """
    }

    private var corePropertiesXML: String {
        let date = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:title>\(xmlEscaped(title)) – تقرير حصر</dc:title>
        <dc:creator>3ERoomElectrical</dc:creator>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(date)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(date)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private var appPropertiesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        <Application>3ERoomElectrical</Application>
        </Properties>
        """
    }

    private func columnName(_ index: Int) -> String {
        var number = index
        var result = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            result = String(
                UnicodeScalar(65 + remainder)!
            ) + result
            number = (number - 1) / 26
        }
        return result
    }

    private func spreadsheetNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
    }
}

private struct StoredZIPArchive {
    private struct Entry {
        let name: String
        let data: Data
        let crc32: UInt32
        let localOffset: UInt32
    }

    private var content = Data()
    private var entries: [Entry] = []

    mutating func add(name: String, text: String) {
        add(name: name, data: Data(text.utf8))
    }

    mutating func add(name: String, data: Data) {
        let nameData = Data(name.utf8)
        let offset = UInt32(content.count)
        let crc = CRC32.checksum(data)

        content.appendUInt32(0x04034B50)
        content.appendUInt16(20)
        content.appendUInt16(0x0800)
        content.appendUInt16(0)
        content.appendUInt16(0)
        content.appendUInt16(0)
        content.appendUInt32(crc)
        content.appendUInt32(UInt32(data.count))
        content.appendUInt32(UInt32(data.count))
        content.appendUInt16(UInt16(nameData.count))
        content.appendUInt16(0)
        content.append(nameData)
        content.append(data)

        entries.append(
            Entry(
                name: name,
                data: data,
                crc32: crc,
                localOffset: offset
            )
        )
    }

    mutating func data() -> Data {
        let centralOffset = UInt32(content.count)

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            content.appendUInt32(0x02014B50)
            content.appendUInt16(20)
            content.appendUInt16(20)
            content.appendUInt16(0x0800)
            content.appendUInt16(0)
            content.appendUInt16(0)
            content.appendUInt16(0)
            content.appendUInt32(entry.crc32)
            content.appendUInt32(UInt32(entry.data.count))
            content.appendUInt32(UInt32(entry.data.count))
            content.appendUInt16(UInt16(nameData.count))
            content.appendUInt16(0)
            content.appendUInt16(0)
            content.appendUInt16(0)
            content.appendUInt16(0)
            content.appendUInt32(0)
            content.appendUInt32(entry.localOffset)
            content.append(nameData)
        }

        let centralSize = UInt32(content.count) - centralOffset
        content.appendUInt32(0x06054B50)
        content.appendUInt16(0)
        content.appendUInt16(0)
        content.appendUInt16(UInt16(entries.count))
        content.appendUInt16(UInt16(entries.count))
        content.appendUInt32(centralSize)
        content.appendUInt32(centralOffset)
        content.appendUInt16(0)
        return content
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1
                ? 0xEDB88320 ^ (crc >> 1)
                : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }
}

private func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private enum TakeoffPDFRenderer {
    private static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private static let margin: CGFloat = 36
    private static let accent = UIColor(
        red: 18 / 255,
        green: 98 / 255,
        blue: 163 / 255,
        alpha: 1
    )
    private static let lightAccent = UIColor(
        red: 232 / 255,
        green: 243 / 255,
        blue: 251 / 255,
        alpha: 1
    )

    static func render(
        title: String,
        rooms: [ExportRoomRecord],
        to url: URL
    ) throws {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(title) – تقرير الحصر",
            kCGPDFContextAuthor as String: "3ERoomElectrical",
            kCGPDFContextCreator as String: "3ERoomElectrical"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        try renderer.writePDF(to: url) { context in
            var state = PDFPageState(
                context: context,
                projectTitle: title,
                documentTitle: "تقرير الحصر"
            )
            state.beginPage()

            let total = ProjectTakeoffSummary(
                rooms: rooms.map(\.summary)
            )
            state.drawSectionTitle("ملخص المشروع")
            let summaryRows: [(String, String)] = [
                ("عدد المسحات", "\(rooms.count)"),
                ("إجمالي الأرضيات", metric(total.floorArea)),
                ("إجمالي الأسقف", metric(total.ceilingArea)),
                ("إجمالي الحوائط", metric(total.grossWallArea)),
                ("خصم الفتحات", metric(total.deductedOpeningArea)),
                ("صافي الحوائط", metric(total.netWallArea)),
                ("الأبواب / الشبابيك / الفتحات", "\(total.doorCount) / \(total.windowCount) / \(total.architecturalOpeningCount)"),
                ("نقاط الكهرباء / إضاءة السقف", "\(total.electricalPointCount) / \(total.ceilingLightCount)")
            ]
            for row in summaryRows {
                state.ensureSpace(29)
                state.drawKeyValue(label: row.0, value: row.1)
            }

            for (roomIndex, room) in rooms.enumerated() {
                state.ensureSpace(185)
                state.drawSectionTitle(
                    "\(roomIndex + 1). \(room.scan.name)"
                )
                if !room.location.isEmpty {
                    state.drawSmallNote("الموقع: \(room.location)")
                }

                state.drawTableHeader(
                    ["البند", "الكمية"],
                    widths: [0.72, 0.28]
                )
                let roomRows: [(String, String)] = [
                    ("مساحة الأرضيات", metric(room.summary.floorArea)),
                    ("مساحة الأسقف", metric(room.summary.ceilingArea)),
                    ("الحوائط الإجمالية", metric(room.summary.grossWallArea)),
                    ("خصم الفتحات", metric(room.summary.deductedOpeningArea)),
                    ("صافي الحوائط", metric(room.summary.netWallArea)),
                    ("الأبواب", "\(room.summary.doorCount)"),
                    ("الشبابيك", "\(room.summary.windowCount)"),
                    ("الفتحات المعمارية", "\(room.summary.architecturalOpeningCount)"),
                    ("نقاط الكهرباء", "\(room.summary.electricalPointCount)"),
                    ("إضاءة السقف", "\(room.summary.ceilingLightCount)")
                ]
                for values in roomRows {
                    state.ensureSpace(25)
                    state.drawTableRow(
                        [values.0, values.1],
                        widths: [0.72, 0.28]
                    )
                }

                if !room.summary.electrical.isEmpty {
                    state.ensureSpace(76)
                    state.drawSubsectionTitle("تفاصيل الكهرباء")
                    state.drawTableHeader(
                        ["العنصر", "الحالة", "العدد"],
                        widths: [0.58, 0.24, 0.18]
                    )
                    for line in room.summary.electrical {
                        state.ensureSpace(25)
                        state.drawTableRow(
                            [
                                line.type.title,
                                line.status.title,
                                "\(line.count)"
                            ],
                            widths: [0.58, 0.24, 0.18]
                        )
                    }
                }
            }

            state.drawFooterOnCurrentPage()
        }
    }

    private static func metric(_ value: Float) -> String {
        String(format: "%.2f م²", value)
    }

    private struct PDFPageState {
        let context: UIGraphicsPDFRendererContext
        let projectTitle: String
        let documentTitle: String
        var y: CGFloat = 0
        var pageNumber = 0

        private var contentWidth: CGFloat {
            TakeoffPDFRenderer.page.width - TakeoffPDFRenderer.margin * 2
        }

        mutating func beginPage() {
            if pageNumber > 0 {
                drawFooterOnCurrentPage()
            }
            context.beginPage()
            pageNumber += 1
            y = TakeoffPDFRenderer.margin

            let headerRect = CGRect(
                x: TakeoffPDFRenderer.margin,
                y: y,
                width: contentWidth,
                height: 66
            )
            TakeoffPDFRenderer.accent.setFill()
            UIBezierPath(
                roundedRect: headerRect,
                cornerRadius: 9
            ).fill()
            drawText(
                "3ERoomElectrical",
                in: CGRect(
                    x: headerRect.minX + 14,
                    y: headerRect.minY + 10,
                    width: 180,
                    height: 22
                ),
                font: .boldSystemFont(ofSize: 13),
                color: .white,
                alignment: .left
            )
            drawText(
                documentTitle,
                in: CGRect(
                    x: headerRect.minX + 200,
                    y: headerRect.minY + 8,
                    width: headerRect.width - 214,
                    height: 24
                ),
                font: .boldSystemFont(ofSize: 18),
                color: .white
            )
            drawText(
                projectTitle,
                in: CGRect(
                    x: headerRect.minX + 14,
                    y: headerRect.minY + 35,
                    width: headerRect.width - 28,
                    height: 20
                ),
                font: .systemFont(ofSize: 11),
                color: UIColor.white.withAlphaComponent(0.9)
            )
            y = headerRect.maxY + 18
        }

        mutating func ensureSpace(_ height: CGFloat) {
            let bottom = TakeoffPDFRenderer.page.height
                - TakeoffPDFRenderer.margin
                - 28
            if y + height > bottom {
                beginPage()
            }
        }

        mutating func drawSectionTitle(_ value: String) {
            ensureSpace(44)
            let rect = CGRect(
                x: TakeoffPDFRenderer.margin,
                y: y,
                width: contentWidth,
                height: 34
            )
            TakeoffPDFRenderer.lightAccent.setFill()
            UIBezierPath(
                roundedRect: rect,
                cornerRadius: 6
            ).fill()
            drawText(
                value,
                in: rect.insetBy(dx: 10, dy: 6),
                font: .boldSystemFont(ofSize: 14),
                color: TakeoffPDFRenderer.accent
            )
            y = rect.maxY + 8
        }

        mutating func drawSubsectionTitle(_ value: String) {
            ensureSpace(32)
            drawText(
                value,
                in: CGRect(
                    x: TakeoffPDFRenderer.margin,
                    y: y,
                    width: contentWidth,
                    height: 24
                ),
                font: .boldSystemFont(ofSize: 12),
                color: TakeoffPDFRenderer.accent
            )
            y += 28
        }

        mutating func drawSmallNote(_ value: String) {
            drawText(
                value,
                in: CGRect(
                    x: TakeoffPDFRenderer.margin,
                    y: y,
                    width: contentWidth,
                    height: 20
                ),
                font: .systemFont(ofSize: 10),
                color: .darkGray
            )
            y += 24
        }

        mutating func drawKeyValue(label: String, value: String) {
            let rowRect = CGRect(
                x: TakeoffPDFRenderer.margin,
                y: y,
                width: contentWidth,
                height: 25
            )
            UIColor(
                white: Int(y / 25).isMultiple(of: 2) ? 0.97 : 1,
                alpha: 1
            ).setFill()
            UIBezierPath(rect: rowRect).fill()
            drawText(
                value,
                in: CGRect(
                    x: rowRect.minX + 8,
                    y: rowRect.minY + 4,
                    width: rowRect.width * 0.33,
                    height: 18
                ),
                font: .boldSystemFont(ofSize: 10),
                color: TakeoffPDFRenderer.accent,
                alignment: .center
            )
            drawText(
                label,
                in: CGRect(
                    x: rowRect.minX + rowRect.width * 0.35,
                    y: rowRect.minY + 4,
                    width: rowRect.width * 0.63,
                    height: 18
                ),
                font: .systemFont(ofSize: 10),
                color: .black
            )
            y = rowRect.maxY + 2
        }

        mutating func drawTableHeader(
            _ values: [String],
            widths: [CGFloat]
        ) {
            ensureSpace(28)
            drawTableCells(
                values,
                widths: widths,
                background: TakeoffPDFRenderer.accent,
                color: .white,
                font: .boldSystemFont(ofSize: 9.5),
                height: 25
            )
        }

        mutating func drawTableRow(
            _ values: [String],
            widths: [CGFloat]
        ) {
            drawTableCells(
                values,
                widths: widths,
                background: .white,
                color: .black,
                font: .systemFont(ofSize: 9),
                height: 23
            )
        }

        mutating func drawTableCells(
            _ values: [String],
            widths: [CGFloat],
            background: UIColor,
            color: UIColor,
            font: UIFont,
            height: CGFloat
        ) {
            var rightEdge = TakeoffPDFRenderer.page.width
                - TakeoffPDFRenderer.margin
            for index in values.indices {
                let width = contentWidth * widths[index]
                let rect = CGRect(
                    x: rightEdge - width,
                    y: y,
                    width: width,
                    height: height
                )
                background.setFill()
                UIBezierPath(rect: rect).fill()
                UIColor(white: 0.84, alpha: 1).setStroke()
                UIBezierPath(rect: rect).stroke()
                drawText(
                    values[index],
                    in: rect.insetBy(dx: 6, dy: 4),
                    font: font,
                    color: color,
                    alignment: index == values.count - 1
                        ? .center
                        : .right
                )
                rightEdge -= width
            }
            y += height
        }

        func drawFooterOnCurrentPage() {
            let footerY = TakeoffPDFRenderer.page.height
                - TakeoffPDFRenderer.margin
                + 4
            UIColor(white: 0.8, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(
                to: CGPoint(
                    x: TakeoffPDFRenderer.margin,
                    y: footerY - 8
                )
            )
            line.addLine(
                to: CGPoint(
                    x: TakeoffPDFRenderer.page.width
                        - TakeoffPDFRenderer.margin,
                    y: footerY - 8
                )
            )
            line.stroke()
            drawText(
                "صفحة \(pageNumber)",
                in: CGRect(
                    x: TakeoffPDFRenderer.margin,
                    y: footerY,
                    width: 90,
                    height: 14
                ),
                font: .systemFont(ofSize: 8),
                color: .gray,
                alignment: .left
            )
            drawText(
                formattedDate(),
                in: CGRect(
                    x: TakeoffPDFRenderer.page.width
                        - TakeoffPDFRenderer.margin - 150,
                    y: footerY,
                    width: 150,
                    height: 14
                ),
                font: .systemFont(ofSize: 8),
                color: .gray
            )
        }

        private func formattedDate() -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ar")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: Date())
        }
    }
}

private enum PlanPDFRenderer {
    private static let page = CGRect(
        x: 0,
        y: 0,
        width: 1190.55,
        height: 841.89
    )
    private static let margin: CGFloat = 28
    private static let accent = UIColor(
        red: 18 / 255,
        green: 98 / 255,
        blue: 163 / 255,
        alpha: 1
    )

    static func render(
        title: String,
        rooms: [ExportRoomRecord],
        to url: URL
    ) throws {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(title) – مخطط 2D",
            kCGPDFContextAuthor as String: "3ERoomElectrical",
            kCGPDFContextCreator as String: "3ERoomElectrical"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        try renderer.writePDF(to: url) { context in
            for (index, record) in rooms.enumerated() {
                context.beginPage()
                drawPage(
                    context: context.cgContext,
                    record: record,
                    index: index + 1,
                    pageCount: rooms.count
                )
            }
        }
    }

    private static func drawPage(
        context: CGContext,
        record: ExportRoomRecord,
        index: Int,
        pageCount: Int
    ) {
        UIColor.white.setFill()
        UIBezierPath(rect: page).fill()

        let header = CGRect(
            x: margin,
            y: margin,
            width: page.width - margin * 2,
            height: 58
        )
        accent.setFill()
        UIBezierPath(
            roundedRect: header,
            cornerRadius: 8
        ).fill()
        drawText(
            "مخطط 2D – كامل الطبقات",
            in: CGRect(
                x: header.midX,
                y: header.minY + 8,
                width: header.width / 2 - 15,
                height: 22
            ),
            font: .boldSystemFont(ofSize: 17),
            color: .white
        )
        drawText(
            record.scan.name,
            in: CGRect(
                x: header.midX,
                y: header.minY + 32,
                width: header.width / 2 - 15,
                height: 17
            ),
            font: .systemFont(ofSize: 10),
            color: UIColor.white.withAlphaComponent(0.9)
        )
        drawText(
            "3ERoomElectrical",
            in: CGRect(
                x: header.minX + 16,
                y: header.minY + 9,
                width: 200,
                height: 20
            ),
            font: .boldSystemFont(ofSize: 14),
            color: .white,
            alignment: .left
        )
        let location = record.location.isEmpty
            ? "المشروع"
            : record.location
        drawText(
            "\(location)  •  صفحة \(index) من \(pageCount)",
            in: CGRect(
                x: header.minX + 16,
                y: header.minY + 33,
                width: header.width / 2 - 30,
                height: 16
            ),
            font: .systemFont(ofSize: 9),
            color: UIColor.white.withAlphaComponent(0.9),
            alignment: .left
        )

        let legendRect = CGRect(
            x: margin,
            y: header.maxY + 10,
            width: 230,
            height: page.height - header.maxY - margin - 20
        )
        let drawingRect = CGRect(
            x: legendRect.maxX + 12,
            y: header.maxY + 10,
            width: page.width - legendRect.maxX - margin - 12,
            height: legendRect.height
        )
        drawLegend(record: record, in: legendRect)
        drawPlan(
            record.project,
            in: drawingRect,
            context: context
        )
    }

    private static func drawLegend(
        record: ExportRoomRecord,
        in rect: CGRect
    ) {
        UIColor(white: 0.97, alpha: 1).setFill()
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: 8
        ).fill()
        UIColor(white: 0.84, alpha: 1).setStroke()
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: 8
        ).stroke()

        var y = rect.minY + 14
        drawText(
            "الطبقات المصدّرة",
            in: CGRect(
                x: rect.minX + 10,
                y: y,
                width: rect.width - 20,
                height: 22
            ),
            font: .boldSystemFont(ofSize: 12),
            color: accent
        )
        y += 31

        let layers: [(String, UIColor)] = [
            ("الأرضيات", UIColor(white: 0.78, alpha: 1)),
            ("الحوائط والأبعاد", accent),
            ("الأبواب", .systemOrange),
            ("الشبابيك", .systemCyan),
            ("الفتحات", .systemPurple),
            ("الفرش", .systemGray),
            ("كهرباء موجود", .systemGreen),
            ("كهرباء مقترح", .systemOrange),
            ("إضاءة السقف", .systemYellow),
            ("أبعاد الكهرباء", .systemIndigo)
        ]
        for layer in layers {
            let swatch = CGRect(
                x: rect.maxX - 28,
                y: y + 3,
                width: 12,
                height: 12
            )
            layer.1.setFill()
            UIBezierPath(
                roundedRect: swatch,
                cornerRadius: 3
            ).fill()
            drawText(
                layer.0,
                in: CGRect(
                    x: rect.minX + 12,
                    y: y,
                    width: rect.width - 48,
                    height: 18
                ),
                font: .systemFont(ofSize: 9),
                color: .black
            )
            y += 23
        }

        y += 8
        UIColor(white: 0.84, alpha: 1).setStroke()
        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: rect.minX + 12, y: y))
        separator.addLine(to: CGPoint(x: rect.maxX - 12, y: y))
        separator.stroke()
        y += 12

        let summary = record.summary
        let values = [
            "الأرضيات: \(String(format: "%.2f", summary.floorArea)) م²",
            "صافي الحوائط: \(String(format: "%.2f", summary.netWallArea)) م²",
            "الكهرباء: \(summary.electricalPointCount) نقطة",
            "إضاءة السقف: \(summary.ceilingLightCount) وحدة"
        ]
        for value in values {
            drawText(
                value,
                in: CGRect(
                    x: rect.minX + 12,
                    y: y,
                    width: rect.width - 24,
                    height: 18
                ),
                font: .systemFont(ofSize: 9),
                color: .darkGray
            )
            y += 22
        }

        drawText(
            "ملاحظة: أبعاد الرسم بالمتر، وجميع الطبقات ظاهرة في هذا التصدير.",
            in: CGRect(
                x: rect.minX + 12,
                y: rect.maxY - 54,
                width: rect.width - 24,
                height: 42
            ),
            font: .systemFont(ofSize: 8),
            color: .gray
        )
    }

    private static func drawPlan(
        _ project: RoomProject,
        in rect: CGRect,
        context: CGContext
    ) {
        UIColor.white.setFill()
        UIBezierPath(rect: rect).fill()
        UIColor(white: 0.82, alpha: 1).setStroke()
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: 8
        ).stroke()

        guard let projection = PlanProjection(
            project: project,
            targetRect: rect.insetBy(dx: 38, dy: 38)
        ) else {
            drawText(
                "لا توجد هندسة صالحة للرسم.",
                in: rect,
                font: .boldSystemFont(ofSize: 16),
                color: .gray,
                alignment: .center
            )
            return
        }

        context.saveGState()
        context.clip(to: rect.insetBy(dx: 2, dy: 2))
        drawGrid(in: rect, scale: projection.scale)

        for floor in project.floors ?? [] {
            let points = floorCorners(
                matrix: floor.matrix,
                width: floor.width,
                depth: floor.depth
            ).map(projection.map)
            drawPolygon(
                points,
                fill: UIColor(white: 0.89, alpha: 0.65),
                stroke: UIColor(white: 0.68, alpha: 1),
                lineWidth: 1.2
            )
        }

        for object in project.objects ?? [] {
            let points = rectangleCorners(
                matrix: object.matrix,
                width: object.width,
                depth: object.depth
            ).map(projection.map)
            drawPolygon(
                points,
                fill: UIColor.systemGray5,
                stroke: UIColor.systemGray,
                lineWidth: 1
            )
            let center = projection.map(planCenter(object.matrix))
            drawCenteredLabel(
                object.title,
                at: center,
                color: .darkGray,
                fontSize: 7.5
            )
        }

        for wall in project.walls {
            let endpoints = lineEndpoints(
                matrix: wall.matrix,
                width: wall.width
            )
            let first = projection.map(endpoints.0)
            let second = projection.map(endpoints.1)
            drawLine(
                from: first,
                to: second,
                color: accent,
                width: 4
            )
            let midpoint = CGPoint(
                x: (first.x + second.x) / 2,
                y: (first.y + second.y) / 2
            )
            drawDimensionLabel(
                String(format: "%.2f م", wall.width),
                at: midpoint,
                color: accent
            )
        }

        for surface in project.surfaces {
            let endpoints = lineEndpoints(
                matrix: surface.matrix,
                width: surface.width
            )
            let first = projection.map(endpoints.0)
            let second = projection.map(endpoints.1)
            let color: UIColor
            switch surface.kind {
            case .door: color = .systemOrange
            case .window: color = .systemCyan
            case .opening: color = .systemPurple
            }
            drawLine(
                from: first,
                to: second,
                color: color,
                width: 6
            )
            let center = CGPoint(
                x: (first.x + second.x) / 2,
                y: (first.y + second.y) / 2
            )
            drawDimensionLabel(
                "\(surfaceKindTitle(surface.kind)) \(String(format: "%.2f", surface.width)) م",
                at: CGPoint(x: center.x, y: center.y + 11),
                color: color
            )
        }

        for point in project.points {
            guard let world = electricalWorldPosition(
                point,
                project: project
            ) else {
                continue
            }
            let center = projection.map(world)
            let color = color(
                hex: point.colorHex,
                fallback: point.status == .existing
                    ? .systemGreen
                    : .systemOrange
            )
            color.setFill()
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - 4.5,
                    y: center.y - 4.5,
                    width: 9,
                    height: 9
                )
            ).fill()
            UIColor.white.setStroke()
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - 4.5,
                    y: center.y - 4.5,
                    width: 9,
                    height: 9
                )
            ).stroke()
            drawCenteredLabel(
                shortElectricalTitle(point.type),
                at: CGPoint(x: center.x, y: center.y - 12),
                color: color,
                fontSize: 6.5
            )
            drawElectricalDimensions(
                point,
                project: project,
                at: center
            )
        }

        for light in project.ceilingLights ?? [] {
            guard light.worldPosition.count >= 3 else { continue }
            let center = projection.map(
                SIMD2(light.worldPosition[0], light.worldPosition[2])
            )
            let radius = max(
                3.5,
                CGFloat(light.diameterMeters)
                    * projection.scale / 2
            )
            let lightColor = color(
                hex: light.colorHex,
                fallback: .systemYellow
            )
            lightColor.withAlphaComponent(
                CGFloat(max(light.brightness, 0.25))
            ).setFill()
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ).fill()
            UIColor.systemOrange.setStroke()
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ).stroke()
            let cross = UIBezierPath()
            cross.move(
                to: CGPoint(x: center.x - radius, y: center.y)
            )
            cross.addLine(
                to: CGPoint(x: center.x + radius, y: center.y)
            )
            cross.move(
                to: CGPoint(x: center.x, y: center.y - radius)
            )
            cross.addLine(
                to: CGPoint(x: center.x, y: center.y + radius)
            )
            cross.stroke()
        }
        context.restoreGState()
    }

    private static func drawGrid(in rect: CGRect, scale: CGFloat) {
        let meter = max(24, scale)
        UIColor(white: 0.93, alpha: 1).setStroke()
        let grid = UIBezierPath()
        var x = rect.minX
        while x <= rect.maxX {
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += meter
        }
        var y = rect.minY
        while y <= rect.maxY {
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += meter
        }
        grid.lineWidth = 0.35
        grid.stroke()
    }

    private static func drawElectricalDimensions(
        _ point: ElectricalPoint,
        project: RoomProject,
        at position: CGPoint
    ) {
        guard let wall = project.walls.first(
            where: { $0.id == point.wallID }
        ) else {
            return
        }
        let fromStart = max(0, point.localX + wall.width / 2)
        let fromEnd = max(0, wall.width / 2 - point.localX)
        drawDimensionLabel(
            String(
                format: "%.2f | %.2f م",
                fromStart,
                fromEnd
            ),
            at: CGPoint(x: position.x, y: position.y + 13),
            color: .systemIndigo
        )
    }

    private static func electricalWorldPosition(
        _ point: ElectricalPoint,
        project: RoomProject
    ) -> SIMD2<Float>? {
        if point.worldPosition.count >= 3 {
            return SIMD2(
                point.worldPosition[0],
                point.worldPosition[2]
            )
        }
        guard let wall = project.walls.first(
            where: { $0.id == point.wallID }
        ) else {
            return nil
        }
        let world = simd_mul(
            wall.matrix,
            SIMD4(point.localX, point.localY, 0, 1)
        )
        return SIMD2(world.x, world.z)
    }

    private static func shortElectricalTitle(
        _ type: ElectricalDeviceType
    ) -> String {
        switch type {
        case .socket: "فيش"
        case .singleSwitch: "مفتاح"
        case .doubleSwitch: "مفتاح 2"
        case .tripleSwitch: "مفتاح 3"
        case .airConditionerSwitch: "مفتاح تكييف"
        case .heaterSwitch: "مفتاح سخان"
        case .shutterSwitch: "مفتاح شتر"
        case .heaterSocket: "فيش سخان"
        case .wallLight: "إضاءة حائط"
        case .dataOutlet: "نت"
        case .mountedDataOutlet: "نت علوي"
        case .telephoneOutlet: "تليفون"
        case .mountedTelephoneOutlet: "تليفون علوي"
        case .televisionOutlet: "تلفزيون"
        case .mountedTelevisionOutlet: "تلفزيون علوي"
        case .splitAirConditioner: "سبليت"
        case .windowAirConditioner: "تكييف شباك"
        }
    }

    private static func surfaceKindTitle(
        _ kind: SurfaceSnapshot.Kind
    ) -> String {
        switch kind {
        case .door: "باب"
        case .window: "شباك"
        case .opening: "فتحة"
        }
    }

    private static func lineEndpoints(
        matrix: simd_float4x4,
        width: Float
    ) -> (SIMD2<Float>, SIMD2<Float>) {
        let center = planCenter(matrix)
        let axis = planAxis(
            SIMD2(matrix.columns.0.x, matrix.columns.0.z)
        )
        return (
            center - axis * (width / 2),
            center + axis * (width / 2)
        )
    }

    private static func rectangleCorners(
        matrix: simd_float4x4,
        width: Float,
        depth: Float
    ) -> [SIMD2<Float>] {
        let center = planCenter(matrix)
        let xAxis = planAxis(
            SIMD2(matrix.columns.0.x, matrix.columns.0.z)
        )
        var depthAxis = planAxis(
            SIMD2(matrix.columns.2.x, matrix.columns.2.z)
        )
        if abs(simd_dot(xAxis, depthAxis)) > 0.95 {
            depthAxis = SIMD2(-xAxis.y, xAxis.x)
        }
        let x = xAxis * (width / 2)
        let z = depthAxis * (depth / 2)
        return [
            center - x - z,
            center + x - z,
            center + x + z,
            center - x + z
        ]
    }

    private static func floorCorners(
        matrix: simd_float4x4,
        width: Float,
        depth: Float
    ) -> [SIMD2<Float>] {
        let center = planCenter(matrix)
        let xAxis = planAxis(
            SIMD2(matrix.columns.0.x, matrix.columns.0.z)
        )
        var depthAxis = planAxis(
            SIMD2(matrix.columns.1.x, matrix.columns.1.z)
        )
        if abs(simd_dot(xAxis, depthAxis)) > 0.95 {
            depthAxis = SIMD2(-xAxis.y, xAxis.x)
        }
        let x = xAxis * (width / 2)
        let z = depthAxis * (depth / 2)
        return [
            center - x - z,
            center + x - z,
            center + x + z,
            center - x + z
        ]
    }

    private static func planCenter(
        _ matrix: simd_float4x4
    ) -> SIMD2<Float> {
        SIMD2(matrix.columns.3.x, matrix.columns.3.z)
    }

    private static func planAxis(
        _ value: SIMD2<Float>
    ) -> SIMD2<Float> {
        let length = simd_length(value)
        return length > 0.0001
            ? value / length
            : SIMD2(1, 0)
    }

    private static func drawPolygon(
        _ points: [CGPoint],
        fill: UIColor,
        stroke: UIColor,
        lineWidth: CGFloat
    ) {
        guard let first = points.first else { return }
        let path = UIBezierPath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.close()
        fill.setFill()
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.fill()
        path.stroke()
    }

    private static func drawLine(
        from: CGPoint,
        to: CGPoint,
        color: UIColor,
        width: CGFloat
    ) {
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func drawDimensionLabel(
        _ value: String,
        at point: CGPoint,
        color: UIColor
    ) {
        let size = (value as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: 7)]
        )
        let rect = CGRect(
            x: point.x - size.width / 2 - 3,
            y: point.y - 7,
            width: size.width + 6,
            height: 14
        )
        UIColor.white.withAlphaComponent(0.88).setFill()
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: 3
        ).fill()
        drawText(
            value,
            in: rect.insetBy(dx: 2, dy: 2),
            font: .systemFont(ofSize: 7),
            color: color,
            alignment: .center
        )
    }

    private static func drawCenteredLabel(
        _ value: String,
        at point: CGPoint,
        color: UIColor,
        fontSize: CGFloat
    ) {
        drawText(
            value,
            in: CGRect(
                x: point.x - 40,
                y: point.y - 7,
                width: 80,
                height: 14
            ),
            font: .systemFont(ofSize: fontSize),
            color: color,
            alignment: .center
        )
    }

    private static func color(
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

    private struct PlanProjection {
        let minX: Float
        let maxZ: Float
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        init?(project: RoomProject, targetRect: CGRect) {
            var points: [SIMD2<Float>] = []
            for wall in project.walls {
                let endpoints = PlanPDFRenderer.lineEndpoints(
                    matrix: wall.matrix,
                    width: wall.width
                )
                points.append(endpoints.0)
                points.append(endpoints.1)
            }
            for floor in project.floors ?? [] {
                points.append(
                    contentsOf: PlanPDFRenderer.floorCorners(
                        matrix: floor.matrix,
                        width: floor.width,
                        depth: floor.depth
                    )
                )
            }
            for object in project.objects ?? [] {
                points.append(
                    contentsOf: PlanPDFRenderer.rectangleCorners(
                        matrix: object.matrix,
                        width: object.width,
                        depth: object.depth
                    )
                )
            }
            for surface in project.surfaces {
                let endpoints = PlanPDFRenderer.lineEndpoints(
                    matrix: surface.matrix,
                    width: surface.width
                )
                points.append(endpoints.0)
                points.append(endpoints.1)
            }
            points.append(
                contentsOf: project.points.compactMap {
                    PlanPDFRenderer.electricalWorldPosition(
                        $0,
                        project: project
                    )
                }
            )
            points.append(
                contentsOf: (project.ceilingLights ?? []).compactMap {
                    guard $0.worldPosition.count >= 3 else {
                        return nil
                    }
                    return SIMD2(
                        $0.worldPosition[0],
                        $0.worldPosition[2]
                    )
                }
            )

            guard let first = points.first else { return nil }
            let minX = points.reduce(first.x) { min($0, $1.x) }
            let maxX = points.reduce(first.x) { max($0, $1.x) }
            let minZ = points.reduce(first.y) { min($0, $1.y) }
            let maxZ = points.reduce(first.y) { max($0, $1.y) }
            let width = max(maxX - minX, 0.5)
            let depth = max(maxZ - minZ, 0.5)
            let scale = min(
                targetRect.width / CGFloat(width),
                targetRect.height / CGFloat(depth)
            )
            let drawingWidth = CGFloat(width) * scale
            let drawingHeight = CGFloat(depth) * scale

            self.minX = minX
            self.maxZ = maxZ
            self.scale = scale
            offsetX = targetRect.minX
                + (targetRect.width - drawingWidth) / 2
            offsetY = targetRect.minY
                + (targetRect.height - drawingHeight) / 2
        }

        func map(_ point: SIMD2<Float>) -> CGPoint {
            CGPoint(
                x: offsetX + CGFloat(point.x - minX) * scale,
                y: offsetY + CGFloat(maxZ - point.y) * scale
            )
        }
    }
}

private func drawText(
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
