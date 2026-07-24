import Foundation

enum DXFCompatibilityError: LocalizedError {
    case malformedPairs
    case missingSection(String)
    case invalidSectionOrder
    case missingModelSpace
    case invalidEntity(type: String, missingCode: String)
    case duplicateHandle(String)
    case stringTooLong(code: Int)

    var errorDescription: String? {
        switch self {
        case .malformedPairs:
            "تعذر إنشاء DXF لأن بنية أزواج group code غير مكتملة."
        case .missingSection(let section):
            "تعذر إنشاء DXF لأن قسم \(section) غير موجود."
        case .invalidSectionOrder:
            "تعذر إنشاء DXF لأن ترتيب الأقسام غير متوافق مع AutoCAD."
        case .missingModelSpace:
            "تعذر إنشاء DXF لأن تعريف Model Space غير مكتمل."
        case .invalidEntity(let type, let missingCode):
            "تعذر إنشاء DXF لأن كيان \(type) يفتقد \(missingCode)."
        case .duplicateHandle(let handle):
            "تعذر إنشاء DXF بسبب تكرار handle رقم \(handle)."
        case .stringTooLong(let code):
            "تعذر إنشاء DXF لأن قيمة نصية في group code \(code) تتجاوز الحد الآمن."
        }
    }
}

enum DXFCompatibilityValidator {
    private struct Pair {
        let code: Int
        let value: String
    }

    static func validate(_ text: String) throws {
        var lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \Character.isNewline
        ).map(String.init)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard lines.count.isMultiple(of: 2) else {
            throw DXFCompatibilityError.malformedPairs
        }

        var pairs: [Pair] = []
        pairs.reserveCapacity(lines.count / 2)
        var index = 0
        while index < lines.count {
            guard let code = Int(lines[index].trimmingCharacters(
                in: .whitespacesAndNewlines
            )) else {
                throw DXFCompatibilityError.malformedPairs
            }
            let value = lines[index + 1].trimmingCharacters(
                in: .newlines
            )
            if isStringCode(code), value.count > 255 {
                throw DXFCompatibilityError.stringTooLong(code: code)
            }
            pairs.append(Pair(code: code, value: value))
            index += 2
        }

        guard pairs.last?.code == 0,
              pairs.last?.value.uppercased() == "EOF" else {
            throw DXFCompatibilityError.malformedPairs
        }

        var sections: [String] = []
        var currentSection: String?
        var sawModelBlockRecord = false
        var sawModelBlock = false
        var handles: Set<String> = []
        var currentRecordType: String?
        var currentRecordPairs: [Pair] = []

        func validateCurrentRecord() throws {
            guard let type = currentRecordType else { return }
            let upperType = type.uppercased()
            let codes = Set(currentRecordPairs.map(\.code))
            let values100 = currentRecordPairs
                .filter { $0.code == 100 }
                .map { $0.value }
            let handle = currentRecordPairs.first { $0.code == 5 }?.value

            let recordsNeedingUniqueHandle: Set<String> = [
                "LTYPE", "LAYER", "STYLE", "BLOCK_RECORD", "BLOCK",
                "ENDBLK", "LINE", "LWPOLYLINE", "CIRCLE", "TEXT",
                "MTEXT", "VIEWPORT", "DICTIONARY", "LAYOUT"
            ]
            if recordsNeedingUniqueHandle.contains(upperType) {
                guard let handle, !handle.isEmpty else {
                    throw DXFCompatibilityError.invalidEntity(
                        type: upperType,
                        missingCode: "handle (5)"
                    )
                }
                if handles.contains(handle) {
                    throw DXFCompatibilityError.duplicateHandle(handle)
                }
                handles.insert(handle)
            }

            let graphicalSubclasses: [String: String] = [
                "LINE": "AcDbLine",
                "LWPOLYLINE": "AcDbPolyline",
                "CIRCLE": "AcDbCircle",
                "TEXT": "AcDbText",
                "MTEXT": "AcDbMText",
                "VIEWPORT": "AcDbViewport"
            ]
            if let subclass = graphicalSubclasses[upperType] {
                guard codes.contains(330) else {
                    throw DXFCompatibilityError.invalidEntity(
                        type: upperType,
                        missingCode: "owner (330)"
                    )
                }
                guard codes.contains(8) else {
                    throw DXFCompatibilityError.invalidEntity(
                        type: upperType,
                        missingCode: "layer (8)"
                    )
                }
                guard values100.contains("AcDbEntity") else {
                    throw DXFCompatibilityError.invalidEntity(
                        type: upperType,
                        missingCode: "AcDbEntity subclass"
                    )
                }
                guard values100.contains(subclass) else {
                    throw DXFCompatibilityError.invalidEntity(
                        type: upperType,
                        missingCode: "\(subclass) subclass"
                    )
                }
            }

            if upperType == "BLOCK_RECORD",
               currentRecordPairs.contains(where: {
                   $0.code == 2 && $0.value == "*Model_Space"
               }) {
                sawModelBlockRecord = true
            }
            if upperType == "BLOCK",
               currentRecordPairs.contains(where: {
                   $0.code == 2 && $0.value == "*Model_Space"
               }) {
                sawModelBlock = true
            }
        }

        index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 {
                try validateCurrentRecord()
                currentRecordType = nil
                currentRecordPairs.removeAll(keepingCapacity: true)

                let upperValue = pair.value.uppercased()
                if upperValue == "SECTION" {
                    guard index + 1 < pairs.count,
                          pairs[index + 1].code == 2 else {
                        throw DXFCompatibilityError.malformedPairs
                    }
                    currentSection = pairs[index + 1].value.uppercased()
                    sections.append(currentSection!)
                    index += 2
                    continue
                }
                if upperValue == "ENDSEC" {
                    currentSection = nil
                    index += 1
                    continue
                }
                if upperValue != "EOF",
                   currentSection != nil,
                   !["TABLE", "ENDTAB"].contains(upperValue) {
                    currentRecordType = upperValue
                }
            } else if currentRecordType != nil {
                currentRecordPairs.append(pair)
            }
            index += 1
        }
        try validateCurrentRecord()

        for required in ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"] {
            guard sections.contains(required) else {
                throw DXFCompatibilityError.missingSection(required)
            }
        }
        let expectedOrder = ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"]
        let positions = try expectedOrder.map { section -> Int in
            guard let position = sections.firstIndex(of: section) else {
                throw DXFCompatibilityError.missingSection(section)
            }
            return position
        }
        guard zip(positions, positions.dropFirst()).allSatisfy(<) else {
            throw DXFCompatibilityError.invalidSectionOrder
        }
        guard sawModelBlockRecord, sawModelBlock else {
            throw DXFCompatibilityError.missingModelSpace
        }
    }

    private static func isStringCode(_ code: Int) -> Bool {
        (0...9).contains(code)
            || (100...102).contains(code)
            || (300...309).contains(code)
            || (410...419).contains(code)
            || (430...439).contains(code)
            || (470...479).contains(code)
            || (999...1003).contains(code)
    }
}
