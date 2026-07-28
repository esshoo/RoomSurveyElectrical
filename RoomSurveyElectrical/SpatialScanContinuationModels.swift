import Foundation

enum SpatialScanPauseReason: String, Codable, CaseIterable, Equatable {
    case manual
    case thermalSafety
    case applicationBackground
    case interrupted

    var title: String {
        switch self {
        case .manual:
            "إيقاف يدوي"
        case .thermalSafety:
            "حماية من الحرارة"
        case .applicationBackground:
            "مغادرة التطبيق"
        case .interrupted:
            "انقطاع الجلسة"
        }
    }

    var detail: String {
        switch self {
        case .manual:
            "تم حفظ الجزء المتاح بعد طلب الإيقاف المؤقت."
        case .thermalSafety:
            "تم حفظ الجزء المتاح قبل إيقاف الكاميرا لحماية الهاتف."
        case .applicationBackground:
            "تم حفظ الجزء المتاح عندما غادر التطبيق الواجهة النشطة."
        case .interrupted:
            "تم الاحتفاظ بآخر جزء محفوظ بعد انقطاع جلسة المسح."
        }
    }

    var systemImage: String {
        switch self {
        case .manual:
            "pause.circle.fill"
        case .thermalSafety:
            "thermometer.high"
        case .applicationBackground:
            "iphone.and.arrow.forward"
        case .interrupted:
            "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}

struct SpatialScanContinuationState: Codable, Equatable {
    var reason: SpatialScanPauseReason
    var pausedAt: Date
    var worldMapCapturedAt: Date?

    init(
        reason: SpatialScanPauseReason,
        pausedAt: Date = Date(),
        worldMapCapturedAt: Date? = nil
    ) {
        self.reason = reason
        self.pausedAt = pausedAt
        self.worldMapCapturedAt = worldMapCapturedAt
    }
}

extension RoomProject {
    var hasSavedSpatialScanContinuation: Bool {
        scanContinuationState != nil && worldMapFile != nil
    }
}
