@preconcurrency import CoreLocation
import Foundation
import simd

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

enum SpatialRelocalizationStrictness: String, Codable, CaseIterable, Identifiable {
    case strict
    case balanced
    case flexible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: "صارم"
        case .balanced: "متوازن"
        case .flexible: "مرن"
        }
    }

    var subtitle: String {
        switch self {
        case .strict:
            "يتطلب تطابقًا قويًا لخريطة AR والحائط المرجعي والاتجاه عند توفره. مناسب للمواقع المتشابهة."
        case .balanced:
            "يجمع خريطة AR مع أبعاد آخر حائط وفتحاتِه، ويتجاهل الموقع إذا كان غير متاح أو غير دقيق."
        case .flexible:
            "يسمح بفروق أكبر ويعرض اختلاف الموقع كتنبيه فقط، لكنه لا يتجاوز فشل محاذاة إحداثيات AR."
        }
    }

    var wallDimensionToleranceRatio: Float {
        switch self {
        case .strict: 0.10
        case .balanced: 0.18
        case .flexible: 0.30
        }
    }

    var minimumDetectedWallCoverage: Float {
        switch self {
        case .strict: 0.65
        case .balanced: 0.48
        case .flexible: 0.32
        }
    }

    var headingToleranceDegrees: Double {
        switch self {
        case .strict: 22
        case .balanced: 40
        case .flexible: 70
        }
    }

    var locationDistanceLimitMeters: Double {
        switch self {
        case .strict: 35
        case .balanced: 80
        case .flexible: 180
        }
    }

    var stableFrameCount: Int {
        switch self {
        case .strict: 12
        case .balanced: 8
        case .flexible: 4
        }
    }

    var wallCenterToleranceMeters: Float {
        switch self {
        case .strict: 0.45
        case .balanced: 0.85
        case .flexible: 1.50
        }
    }

    var wallNormalToleranceDegrees: Float {
        switch self {
        case .strict: 16
        case .balanced: 30
        case .flexible: 52
        }
    }

    var timeoutSeconds: Int {
        switch self {
        case .strict: 120
        case .balanced: 105
        case .flexible: 90
        }
    }
}

enum SpatialWorldMapQuality: String, Codable, Equatable {
    case notAvailable
    case limited
    case extending
    case mapped

    var title: String {
        switch self {
        case .notAvailable: "غير متاحة"
        case .limited: "ضعيفة"
        case .extending: "جيدة"
        case .mapped: "ممتازة"
        }
    }

    var isSuitableForResume: Bool {
        self == .extending || self == .mapped
    }
}

struct SpatialOpeningReference: Codable, Equatable {
    var kind: SurfaceSnapshot.Kind
    var centerXRatio: Float
    var widthRatio: Float
    var heightRatio: Float
}

struct SpatialWallReference: Codable, Equatable {
    var wallID: UUID
    var width: Float
    var height: Float
    var transform: [Float]
    var cameraTransform: [Float]?
    var openings: [SpatialOpeningReference]
    var capturedAt: Date

    var wallMatrix: simd_float4x4 {
        simd_float4x4(columnMajorValues: transform)
    }

    var cameraMatrix: simd_float4x4? {
        cameraTransform.map { simd_float4x4(columnMajorValues: $0) }
    }

    var summary: String {
        let widthCM = Int((width * 100).rounded())
        let heightCM = Int((height * 100).rounded())
        if openings.isEmpty {
            return "الحائط المرجعي: \(widthCM) × \(heightCM) سم"
        }
        return "الحائط المرجعي: \(widthCM) × \(heightCM) سم • \(openings.count) فتحة"
    }
}

struct SpatialGeographicReference: Codable, Equatable {
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracyMeters: Double?
    var headingDegrees: Double?
    var headingAccuracyDegrees: Double?
    var capturedAt: Date

    var hasUsableLocation: Bool {
        guard latitude != nil, longitude != nil,
              let accuracy = horizontalAccuracyMeters else { return false }
        return accuracy >= 0 && accuracy <= 150
    }

    var hasUsableHeading: Bool {
        guard headingDegrees != nil,
              let accuracy = headingAccuracyDegrees else { return false }
        return accuracy >= 0 && accuracy <= 55
    }
}

struct SpatialScanContinuationState: Codable, Equatable {
    var reason: SpatialScanPauseReason
    var pausedAt: Date
    var worldMapCapturedAt: Date?
    var worldMapQuality: SpatialWorldMapQuality? = nil
    var referenceWall: SpatialWallReference? = nil
    var referenceImageFile: String? = nil
    var geographicReference: SpatialGeographicReference? = nil
    var referenceAnchorName: String? = nil

    init(
        reason: SpatialScanPauseReason,
        pausedAt: Date = Date(),
        worldMapCapturedAt: Date? = nil,
        worldMapQuality: SpatialWorldMapQuality? = nil,
        referenceWall: SpatialWallReference? = nil,
        referenceImageFile: String? = nil,
        geographicReference: SpatialGeographicReference? = nil,
        referenceAnchorName: String? = nil
    ) {
        self.reason = reason
        self.pausedAt = pausedAt
        self.worldMapCapturedAt = worldMapCapturedAt
        self.worldMapQuality = worldMapQuality
        self.referenceWall = referenceWall
        self.referenceImageFile = referenceImageFile
        self.geographicReference = geographicReference
        self.referenceAnchorName = referenceAnchorName
    }
}

extension RoomProject {
    var hasSavedSpatialScanContinuation: Bool {
        scanContinuationState != nil && worldMapFile != nil
    }
}

@MainActor
final class SpatialReferenceSensor: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var latestLocation: CLLocation?
    private(set) var latestHeading: CLHeading?
    private(set) var isEnabled = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 3
        manager.headingFilter = 3
        manager.headingOrientation = .portrait
    }

    func start(enabled: Bool, requestPermission: Bool) {
        isEnabled = enabled
        guard enabled else {
            stop()
            return
        }

        if requestPermission,
           manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        startAvailableServices()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func snapshot() -> SpatialGeographicReference? {
        guard isEnabled else { return nil }

        let location = latestLocation.flatMap { value -> CLLocation? in
            guard value.horizontalAccuracy >= 0,
                  Date().timeIntervalSince(value.timestamp) <= 60 else { return nil }
            return value
        }
        let heading = latestHeading.flatMap { value -> CLHeading? in
            guard value.headingAccuracy >= 0,
                  Date().timeIntervalSince(value.timestamp) <= 60 else { return nil }
            return value
        }

        guard location != nil || heading != nil else { return nil }
        let resolvedHeading: Double?
        if let heading {
            resolvedHeading = heading.trueHeading >= 0
                ? heading.trueHeading
                : heading.magneticHeading
        } else {
            resolvedHeading = nil
        }

        return SpatialGeographicReference(
            latitude: location.map { roundedCoordinate($0.coordinate.latitude) },
            longitude: location.map { roundedCoordinate($0.coordinate.longitude) },
            horizontalAccuracyMeters: location.map { max($0.horizontalAccuracy, 12) },
            headingDegrees: resolvedHeading.map { ($0 * 10).rounded() / 10 },
            headingAccuracyDegrees: heading?.headingAccuracy,
            capturedAt: Date()
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startAvailableServices()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        latestLocation = locations.last
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        latestHeading = newHeading
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Location and heading are optional evidence. ARKit and wall geometry
        // remain available if the user denies access or the sensor fails.
    }

    private func roundedCoordinate(_ value: Double) -> Double {
        // About 11 m at the equator: enough for same-site confirmation without
        // retaining an unnecessarily precise indoor position.
        (value * 10_000).rounded() / 10_000
    }

    private func startAvailableServices() {
        guard isEnabled else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .notDetermined:
            break
        case .denied, .restricted:
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        @unknown default:
            break
        }
    }
}
