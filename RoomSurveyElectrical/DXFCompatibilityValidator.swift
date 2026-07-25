import Foundation

enum DXFCompatibilityError: LocalizedError {
    case malformedPairs
    case missingSection(String)
    case invalidSectionOrder
    case missingModelEntities
    case paperSpaceNotSupported(String)
    case forbiddenLayoutRecord(String)
    case malformedPolyline
    case stringTooLong(code: Int)
    case nonASCIIData

    var errorDescription: String? {
        switch self {
        case .malformedPairs:
            "تعذر إنشاء DXF لأن بنية أزواج group code غير مكتملة."
        case .missingSection(let section):
            "تعذر إنشاء DXF لأن قسم \(section) غير موجود."
        case .invalidSectionOrder:
            "تعذر إنشاء DXF لأن ترتيب الأقسام غير متوافق."
        case .missingModelEntities:
            "تعذر إنشاء DXF لأن قسم ENTITIES لا يحتوي رسمًا فعليًا في Model Space."
        case .paperSpaceNotSupported(let type):
            "تعذر إنشاء DXF لأن \(type) مرتبط بـPaper Space. التصدير يجب أن يكون Model Space فقط."
        case .forbiddenLayoutRecord(let type):
            "تعذر إنشاء DXF لأن الملف يحتوي سجل \(type) خاصًا بالـLayouts."
        case .malformedPolyline:
            "تعذر إنشاء DXF لأن POLYLINE لا تحتوي VERTEX وSEQEND بصورة صحيحة."
        case .stringTooLong(let code):
            "تعذر إنشاء DXF لأن قيمة نصية في group code \(code) تتجاوز الحد الآمن."
        case .nonASCIIData:
            "تعذر إنشاء DXF لأن ملف R12 يحتوي نص Unicode مباشرًا بدل تحويله إلى خطوط هندسية."
        }
    }
}

enum DXFCompatibilityValidator {
    private struct Pair {
        let code: Int
        let value: String
    }

    static func validate(_ text: String) throws {
        guard text.unicodeScalars.allSatisfy(\.isASCII) else {
            throw DXFCompatibilityError.nonASCIIData
        }
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
        var lineIndex = 0
        while lineIndex < lines.count {
            guard let code = Int(
                lines[lineIndex].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ) else {
                throw DXFCompatibilityError.malformedPairs
            }
            let value = lines[lineIndex + 1]
                .trimmingCharacters(in: .newlines)
            if isStringCode(code), value.utf8.count > 2049 {
                throw DXFCompatibilityError.stringTooLong(code: code)
            }
            pairs.append(Pair(code: code, value: value))
            lineIndex += 2
        }

        guard pairs.last?.code == 0,
              pairs.last?.value.uppercased() == "EOF" else {
            throw DXFCompatibilityError.malformedPairs
        }

        var sections: [String] = []
        var currentSection: String?
        var entityCount = 0
        var polylineOpen = false
        var polylineVertexCount = 0

        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 {
                let type = pair.value.uppercased()
                if type == "SECTION" {
                    guard index + 1 < pairs.count,
                          pairs[index + 1].code == 2 else {
                        throw DXFCompatibilityError.malformedPairs
                    }
                    currentSection = pairs[index + 1].value.uppercased()
                    sections.append(currentSection!)
                    index += 2
                    continue
                }
                if type == "ENDSEC" {
                    if polylineOpen {
                        throw DXFCompatibilityError.malformedPolyline
                    }
                    currentSection = nil
                    index += 1
                    continue
                }

                if ["LAYOUT", "VIEWPORT"].contains(type) {
                    throw DXFCompatibilityError.forbiddenLayoutRecord(type)
                }

                if currentSection == "ENTITIES" {
                    switch type {
                    case "POLYLINE":
                        if polylineOpen {
                            throw DXFCompatibilityError.malformedPolyline
                        }
                        polylineOpen = true
                        polylineVertexCount = 0
                        entityCount += 1
                    case "VERTEX":
                        guard polylineOpen else {
                            throw DXFCompatibilityError.malformedPolyline
                        }
                        polylineVertexCount += 1
                    case "SEQEND":
                        guard polylineOpen, polylineVertexCount >= 2 else {
                            throw DXFCompatibilityError.malformedPolyline
                        }
                        polylineOpen = false
                    case "LINE", "CIRCLE", "TEXT", "ARC", "POINT":
                        entityCount += 1
                    default:
                        break
                    }
                }
            } else {
                if pair.code == 67, Int(pair.value) == 1 {
                    throw DXFCompatibilityError
                        .paperSpaceNotSupported("group code 67")
                }
                if pair.code == 410 {
                    throw DXFCompatibilityError
                        .paperSpaceNotSupported("layout name 410")
                }
            }
            index += 1
        }

        let required = ["HEADER", "TABLES", "BLOCKS", "ENTITIES"]
        for section in required where !sections.contains(section) {
            throw DXFCompatibilityError.missingSection(section)
        }
        if sections.contains("CLASSES") {
            throw DXFCompatibilityError.forbiddenLayoutRecord("CLASSES")
        }
        if sections.contains("OBJECTS") {
            throw DXFCompatibilityError.forbiddenLayoutRecord("OBJECTS")
        }

        let positions = try required.map { section -> Int in
            guard let position = sections.firstIndex(of: section) else {
                throw DXFCompatibilityError.missingSection(section)
            }
            return position
        }
        guard zip(positions, positions.dropFirst()).allSatisfy(<) else {
            throw DXFCompatibilityError.invalidSectionOrder
        }
        guard pairs.contains(where: {
            $0.code == 1 && $0.value.uppercased() == "AC1009"
        }) else {
            throw DXFCompatibilityError.malformedPairs
        }
        guard pairs.contains(where: {
            $0.code == 3 && $0.value.uppercased() == "ANSI_1252"
        }) else {
            throw DXFCompatibilityError.malformedPairs
        }
        guard entityCount > 0 else {
            throw DXFCompatibilityError.missingModelEntities
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
