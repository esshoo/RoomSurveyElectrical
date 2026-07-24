import Foundation

struct ExportDocumentMetadata {
    let brandName: String
    let projectName: String
    let projectCreatedAt: Date
    let exportedAt: Date

    init(
        projectName: String,
        projectCreatedAt: Date,
        exportedAt: Date = Date(),
        brandName: String = "3Essam"
    ) {
        self.brandName = brandName
        self.projectName = projectName
        self.projectCreatedAt = projectCreatedAt
        self.exportedAt = exportedAt
    }

    var projectCreatedText: String {
        Self.displayDateFormatter.string(from: projectCreatedAt)
    }

    var exportedText: String {
        Self.displayDateTimeFormatter.string(from: exportedAt)
    }

    var projectCreatedISO8601: String {
        Self.iso8601Formatter.string(from: projectCreatedAt)
    }

    var exportedISO8601: String {
        Self.iso8601Formatter.string(from: exportedAt)
    }

    var projectLine: String {
        "المشروع: \(projectName) • تاريخ الإنشاء: \(projectCreatedText)"
    }

    var exportLine: String {
        "تاريخ التصدير: \(exportedText)"
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let displayDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy - HH:mm"
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}
