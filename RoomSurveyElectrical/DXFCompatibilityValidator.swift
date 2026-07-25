import Foundation

enum DXFCompatibilityError: LocalizedError {
    case malformedPairs
    case missingSection(String)
    case invalidSectionOrder
    case missingModelEntities
    case paperSpaceNotSupported(String)
    case forbiddenLayoutRecord(String)
    case invalidVersion
    case invalidEncoding
    case missingModelSpaceRecord
    case missingObjectsDictionary
    case invalidEntity(type: String)
    case stringTooLong(code: Int)

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
        case .paperSpaceNotSupported(let value):
            "تعذر إنشاء DXF لأن الملف يحتوي مرجع Paper Space: \(value)."
        case .forbiddenLayoutRecord(let type):
            "تعذر إنشاء DXF لأن الملف يحتوي سجل \(type) خاصًا بالـLayouts."
        case .invalidVersion:
            "تعذر إنشاء DXF لأن الإصدار ليس AutoCAD 2007 (AC1021)."
        case .invalidEncoding:
            "تعذر إنشاء DXF لأن ترميز الملف ليس UTF-8."
        case .missingModelSpaceRecord:
            "تعذر إنشاء DXF لأن تعريف *Model_Space غير مكتمل."
        case .missingObjectsDictionary:
            "تعذر إنشاء DXF لأن قسم OBJECTS أو قاموس ACAD_GROUP المطلوب لملف DXF الحديث غير مكتمل."
        case .invalidEntity(let type):
            "تعذر إنشاء DXF لأن كيان \(type) لا يحتوي بيانات الملكية أو Subclass المطلوبة."
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

    private static let graphicalEntityTypes: Set<String> = [
        "LINE", "LWPOLYLINE", "CIRCLE", "TEXT", "MTEXT", "ARC", "POINT"
    ]

    private static let expectedSubclass: [String: String] = [
        "LINE": "AcDbLine",
        "LWPOLYLINE": "AcDbPolyline",
        "CIRCLE": "AcDbCircle",
        "TEXT": "AcDbText",
        "MTEXT": "AcDbMText",
        "ARC": "AcDbArc",
        "POINT": "AcDbPoint"
    ]

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
        var currentType: String?
        var currentRecord: [Pair] = []
        var modelEntityCount = 0
        var foundModelBlockRecord = false
        var foundModelBlockDefinition = false
        var foundRootDictionaryWithAcadGroup = false
        var foundAcadGroupDictionary = false

        func finishRecord() throws {
            guard let currentType else { return }
            let type = currentType.uppercased()

            if type == "BLOCK_RECORD",
               currentRecord.contains(where: {
                   $0.code == 2 && $0.value == "*Model_Space"
               }),
               currentRecord.contains(where: {
                   $0.code == 5 && $0.value.uppercased() == "31"
               }) {
                foundModelBlockRecord = true
            }

            if type == "BLOCK",
               currentSection == "BLOCKS",
               currentRecord.contains(where: {
                   $0.code == 2 && $0.value == "*Model_Space"
               }),
               currentRecord.contains(where: {
                   $0.code == 330 && $0.value.uppercased() == "31"
               }) {
                foundModelBlockDefinition = true
            }

            if type == "DICTIONARY", currentSection == "OBJECTS" {
                let handle = currentRecord.first(where: { $0.code == 5 })?
                    .value.uppercased()
                let owner = currentRecord.first(where: { $0.code == 330 })?
                    .value.uppercased()
                if handle == "1F0000",
                   owner == "0",
                   currentRecord.contains(where: {
                       $0.code == 3 && $0.value == "ACAD_GROUP"
                   }),
                   currentRecord.contains(where: {
                       $0.code == 350 && $0.value.uppercased() == "1F0001"
                   }) {
                    foundRootDictionaryWithAcadGroup = true
                }
                if handle == "1F0001", owner == "1F0000" {
                    foundAcadGroupDictionary = true
                }
            }

            guard currentSection == "ENTITIES",
                  graphicalEntityTypes.contains(type) else {
                return
            }

            guard currentRecord.contains(where: { $0.code == 5 }),
                  currentRecord.contains(where: {
                      $0.code == 330 && $0.value.uppercased() == "31"
                  }),
                  currentRecord.contains(where: {
                      $0.code == 100 && $0.value == "AcDbEntity"
                  }),
                  currentRecord.contains(where: {
                      $0.code == 410 && $0.value == "Model"
                  }),
                  currentRecord.contains(where: {
                      $0.code == 370
                  }),
                  let subclass = expectedSubclass[type],
                  currentRecord.contains(where: {
                      $0.code == 100 && $0.value == subclass
                  }) else {
                throw DXFCompatibilityError.invalidEntity(type: type)
            }

            if currentRecord.contains(where: {
                $0.code == 67 && Int($0.value) == 1
            }) {
                throw DXFCompatibilityError.paperSpaceNotSupported(type)
            }
            if currentRecord.contains(where: {
                $0.code == 410 && $0.value != "Model"
            }) {
                throw DXFCompatibilityError.paperSpaceNotSupported(type)
            }

            if type == "LWPOLYLINE" {
                let declaredCount = currentRecord.first(where: {
                    $0.code == 90
                }).flatMap { Int($0.value) }
                let xCount = currentRecord.filter { $0.code == 10 }.count
                let yCount = currentRecord.filter { $0.code == 20 }.count
                guard let declaredCount,
                      declaredCount >= 2,
                      declaredCount == xCount,
                      xCount == yCount else {
                    throw DXFCompatibilityError.invalidEntity(type: type)
                }
            }

            if type == "TEXT" || type == "MTEXT" {
                guard currentRecord.contains(where: {
                    ($0.code == 1 || $0.code == 3) && !$0.value.isEmpty
                }) else {
                    throw DXFCompatibilityError.invalidEntity(type: type)
                }
            }

            modelEntityCount += 1
        }

        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 {
                try finishRecord()
                currentType = nil
                currentRecord.removeAll(keepingCapacity: true)

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
                    currentSection = nil
                    index += 1
                    continue
                }
                if ["LAYOUT", "VIEWPORT"].contains(type) {
                    throw DXFCompatibilityError.forbiddenLayoutRecord(type)
                }
                if !["EOF", "TABLE", "ENDTAB"].contains(type) {
                    currentType = type
                }
            } else if currentType != nil {
                currentRecord.append(pair)
            }
            index += 1
        }
        try finishRecord()

        let required = [
            "HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"
        ]
        for section in required where !sections.contains(section) {
            throw DXFCompatibilityError.missingSection(section)
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
            $0.code == 1 && $0.value.uppercased() == "AC1021"
        }) else {
            throw DXFCompatibilityError.invalidVersion
        }
        guard pairs.contains(where: {
            $0.code == 3
                && ["ANSI_1252", "UTF-8"].contains($0.value.uppercased())
        }) else {
            throw DXFCompatibilityError.invalidEncoding
        }
        guard foundModelBlockRecord, foundModelBlockDefinition else {
            throw DXFCompatibilityError.missingModelSpaceRecord
        }
        guard foundRootDictionaryWithAcadGroup, foundAcadGroupDictionary else {
            throw DXFCompatibilityError.missingObjectsDictionary
        }
        guard modelEntityCount > 0 else {
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
