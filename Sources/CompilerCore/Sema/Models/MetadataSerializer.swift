import Foundation

package enum MetadataModality: String, Codable {
    case final
    case open
    case abstract
}

package struct MetadataRecord {
    package let kind: SymbolKind
    package let visibility: Visibility
    package let constructorVisibilityInherited: Bool
    let mangledName: String
    package let fqName: String
    package let arity: Int
    package let isSuspend: Bool
    package let isInline: Bool
    package let isOperator: Bool
    package let isInfix: Bool
    package let isOverride: Bool
    package let isMemberExtension: Bool
    let receiverOwnerFQName: String?
    let typeSignature: String?
    /// Upper-bound type signatures for callable type parameters, in declaration order.
    /// Empty entries preserve alignment when only a later type parameter is bounded.
    package let typeParameterUpperBoundsSignatures: [[String]]
    /// Type parameter references of a callable in declaration order, encoded as
    /// `T<rawID>` tokens (e.g. `T5023`) matching the encoding used inside type
    /// signatures. For member callables this is the full list, including the
    /// leading owner (class) type parameters. It preserves the declared order
    /// for parameters that never appear in the decoded signature ("phantom"
    /// parameters referenced only inside the body via explicit type arguments
    /// to other generic calls) and disambiguates parameters across overloads
    /// that share one FQ name.
    package let callableTypeParameterSignatures: [String]
    package let inputOnlyTypeParameterIndices: Set<Int>
    package let valueParameterIsVararg: [Bool]
    package let valueParameterUnsafeVarianceTypeParameterIndices: [[Int]]
    package let valueParameterAllowsNonLocalReturn: [Bool]
    package let valueParameterCallsInPlaceKinds: [InvocationKind?]
    package let contractImplicationEffects: [ContractImplicationEffect]
    package let valueParameterHasDefaultValues: [Bool]
    package let canThrow: Bool
    package let valueParameterNames: [String]
    package let hasStableParameterNames: Bool
    package let reifiedTypeParameterIndices: Set<Int>
    let defaultStubExternalLinkName: String?
    let externalLinkName: String?
    package let declaredFieldCount: Int?
    package let declaredInstanceSizeWords: Int?
    let declaredVtableSize: Int?
    let declaredItableSize: Int?
    package let superFQName: String?
    package let companionObjectFQName: String?
    let fieldOffsets: String?
    let vtableSlots: String?
    let itableSlots: String?
    let objectInitializerLinkName: String?
    let companionInitializerLinkName: String?
    let objectLazyInitializerLinkName: String?
    package let enumStaticInitLinkName: String?

    package let isDataClass: Bool

    package let isOpenClass: Bool
    package let isInnerClass: Bool
    /// Declaration modality for classes and members. Final is omitted from the
    /// wire format so older artifacts remain compact and decode as final.
    package let modality: MetadataModality

    package let isSealedClass: Bool

    package let isFunInterface: Bool

    let annotations: [MetadataAnnotationRecord]

    package let isValueClass: Bool

    let valueClassUnderlyingTypeSig: String?

    let sealedSubclassFQNames: [String]

    let isExpect: Bool
    let isActual: Bool

    let propertyReceiverTypeSignature: String?
    let propertyGetterExternalLinkName: String?
    let propertySetterExternalLinkName: String?
    let propertySetterVisibility: Visibility?
    let abiReturnTypeSignature: String?
    let propertyGetterAbiReturnTypeSignature: String?
    package let isMutable: Bool
    let nominalTypeParametersSignature: String?
    let nominalSupertypeSignatures: [String]
    let constValueLiteral: String?
    let nominalTypeParameters: String?

    init(
        kind: SymbolKind,
        visibility: Visibility = .public,
        constructorVisibilityInherited: Bool = false,
        mangledName: String = "",
        fqName: String = "",
        arity: Int = 0,
        isSuspend: Bool = false,
        isInline: Bool = false,
        isOperator: Bool = false,
        isInfix: Bool = false,
        isOverride: Bool = false,
        isMemberExtension: Bool = false,
        receiverOwnerFQName: String? = nil,
        typeSignature: String? = nil,
        typeParameterUpperBoundsSignatures: [[String]] = [],
        callableTypeParameterSignatures: [String] = [],
        inputOnlyTypeParameterIndices: Set<Int> = [],
        valueParameterIsVararg: [Bool] = [],
        valueParameterUnsafeVarianceTypeParameterIndices: [[Int]] = [],
        valueParameterAllowsNonLocalReturn: [Bool] = [],
        valueParameterHasDefaultValues: [Bool] = [],
        valueParameterCallsInPlaceKinds: [InvocationKind?] = [],
        contractImplicationEffects: [ContractImplicationEffect] = [],
        canThrow: Bool = false,
        valueParameterNames: [String] = [],
        hasStableParameterNames: Bool = true,
        reifiedTypeParameterIndices: Set<Int> = [],
        defaultStubExternalLinkName: String? = nil,
        externalLinkName: String? = nil,
        declaredFieldCount: Int? = nil,
        declaredInstanceSizeWords: Int? = nil,
        declaredVtableSize: Int? = nil,
        declaredItableSize: Int? = nil,
        superFQName: String? = nil,
        companionObjectFQName: String? = nil,
        fieldOffsets: String? = nil,
        vtableSlots: String? = nil,
        itableSlots: String? = nil,
        objectInitializerLinkName: String? = nil,
        companionInitializerLinkName: String? = nil,
        objectLazyInitializerLinkName: String? = nil,
        enumStaticInitLinkName: String? = nil,
        isDataClass: Bool = false,
        isOpenClass: Bool = false,
        isInnerClass: Bool = false,
        modality: MetadataModality = .final,
        isSealedClass: Bool = false,
        isFunInterface: Bool = false,
        annotations: [MetadataAnnotationRecord] = [],
        isValueClass: Bool = false,
        valueClassUnderlyingTypeSig: String? = nil,
        sealedSubclassFQNames: [String] = [],
        isExpect: Bool = false,
        isActual: Bool = false,
        propertyReceiverTypeSignature: String? = nil,
        propertyGetterExternalLinkName: String? = nil,
        propertySetterExternalLinkName: String? = nil,
        propertySetterVisibility: Visibility? = nil,
        abiReturnTypeSignature: String? = nil,
        propertyGetterAbiReturnTypeSignature: String? = nil,
        isMutable: Bool = false,
        nominalTypeParametersSignature: String? = nil,
        nominalSupertypeSignatures: [String] = [],
        constValueLiteral: String? = nil,
        nominalTypeParameters: String? = nil
    ) {
        self.kind = kind
        self.visibility = visibility
        self.constructorVisibilityInherited = constructorVisibilityInherited
        self.mangledName = mangledName
        self.fqName = fqName
        self.arity = arity
        self.isSuspend = isSuspend
        self.isInline = isInline
        self.isOperator = isOperator
        self.isInfix = isInfix
        self.isOverride = isOverride
        self.isMemberExtension = isMemberExtension
        self.receiverOwnerFQName = receiverOwnerFQName
        self.typeSignature = typeSignature
        self.typeParameterUpperBoundsSignatures = typeParameterUpperBoundsSignatures
        self.callableTypeParameterSignatures = callableTypeParameterSignatures
        self.inputOnlyTypeParameterIndices = inputOnlyTypeParameterIndices
        self.valueParameterIsVararg = valueParameterIsVararg
        self.valueParameterUnsafeVarianceTypeParameterIndices = valueParameterUnsafeVarianceTypeParameterIndices
        self.valueParameterAllowsNonLocalReturn = valueParameterAllowsNonLocalReturn
        self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
        self.valueParameterCallsInPlaceKinds = valueParameterCallsInPlaceKinds
        self.contractImplicationEffects = contractImplicationEffects
        self.canThrow = canThrow
        self.valueParameterNames = valueParameterNames
        self.hasStableParameterNames = hasStableParameterNames
        self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
        self.defaultStubExternalLinkName = defaultStubExternalLinkName
        self.externalLinkName = externalLinkName
        self.declaredFieldCount = declaredFieldCount
        self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
        self.superFQName = superFQName
        self.companionObjectFQName = companionObjectFQName
        self.fieldOffsets = fieldOffsets
        self.vtableSlots = vtableSlots
        self.itableSlots = itableSlots
        self.objectInitializerLinkName = objectInitializerLinkName
        self.companionInitializerLinkName = companionInitializerLinkName
        self.objectLazyInitializerLinkName = objectLazyInitializerLinkName
        self.enumStaticInitLinkName = enumStaticInitLinkName
        self.isDataClass = isDataClass
        self.isOpenClass = isOpenClass
        self.isInnerClass = isInnerClass
        self.modality = modality
        self.isSealedClass = isSealedClass
        self.isFunInterface = isFunInterface
        self.annotations = annotations
        self.isValueClass = isValueClass
        self.valueClassUnderlyingTypeSig = valueClassUnderlyingTypeSig
        self.sealedSubclassFQNames = sealedSubclassFQNames
        self.isExpect = isExpect
        self.isActual = isActual
        self.propertyReceiverTypeSignature = propertyReceiverTypeSignature
        self.propertyGetterExternalLinkName = propertyGetterExternalLinkName
        self.propertySetterExternalLinkName = propertySetterExternalLinkName
        self.propertySetterVisibility = propertySetterVisibility
        self.abiReturnTypeSignature = abiReturnTypeSignature
        self.propertyGetterAbiReturnTypeSignature = propertyGetterAbiReturnTypeSignature
        self.isMutable = isMutable
        self.nominalTypeParametersSignature = nominalTypeParametersSignature
        self.nominalSupertypeSignatures = nominalSupertypeSignatures
        self.constValueLiteral = constValueLiteral
        self.nominalTypeParameters = nominalTypeParameters
    }
}

public struct MetadataAnnotationRecord: Equatable, Codable {
    public let annotationFQName: String
    public let arguments: [String]
    public let useSiteTarget: String?
    public let retention: AnnotationRetentionKind?
    public let usageID: String?
    public let factorySymbol: SymbolID?
    public let factoryLinkName: String?

    public init(
        annotationFQName: String,
        arguments: [String] = [],
        useSiteTarget: String? = nil,
        retention: AnnotationRetentionKind? = nil,
        usageID: String? = nil,
        factorySymbol: SymbolID? = nil,
        factoryLinkName: String? = nil
    ) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.useSiteTarget = useSiteTarget
        self.retention = retention
        self.usageID = usageID
        self.factorySymbol = factorySymbol
        self.factoryLinkName = factoryLinkName
    }
}

private final class LegacyMetadataIndexRecord {
    let record: MetadataRecord
    init(_ record: MetadataRecord) { self.record = record }
}

/// Offsets and lengths are UTF-8 bytes relative to the body section.
struct MetadataIndexEntry {
    let offset: Int
    let length: Int
    private let legacyRecord: LegacyMetadataIndexRecord?
    let compactRecord: CompactMetadataIndexRecord?
    var record: MetadataRecord { legacyRecord?.record ?? compactRecord!.record }
    var fqName: String { compactRecord?.fqName ?? record.fqName }
    var nominalTypeParametersSignature: String? {
        if let compactRecord { return compactRecord.nominalTypeParametersSignature }
        return record.nominalTypeParametersSignature
    }

    init(offset: Int, length: Int, record: MetadataRecord, hasCompleteInitializerInfo: Bool = false) {
        self.offset = offset
        self.length = length
        legacyRecord = LegacyMetadataIndexRecord(record)
        compactRecord = nil
        self.hasCompleteInitializerInfo = hasCompleteInitializerInfo
    }

    init(offset: Int, length: Int, compactRecord: CompactMetadataIndexRecord) {
        self.offset = offset
        self.length = length
        legacyRecord = nil
        self.compactRecord = compactRecord
        hasCompleteInitializerInfo = compactRecord.hasCompleteInitializerInfo
    }

    /// Older v2 indexes omit initializer links; absence is unknown there.
    var hasCompleteInitializerInfo: Bool = false
}

final class IndexedMetadataFile {
    let metadataVersion: Int
    let entries: [MetadataIndexEntry]

    private let data: Data
    private let bodyStart: Int
    private var decodedRecords: [Int: MetadataRecord] = [:]
    private lazy var entriesSortedByFQName = entries.indices.sorted {
        let left = entries[$0].fqName
        let right = entries[$1].fqName
        return left == right ? $0 < $1 : left < right
    }
    private lazy var entriesSortedByShortName = entries.indices.sorted {
        let left = Self.shortName(entries[$0].fqName)
        let right = Self.shortName(entries[$1].fqName)
        return left == right ? $0 < $1 : left < right
    }
    private lazy var entriesSortedByReceiverOwner = entries.indices.filter {
        entries[$0].compactRecord?.receiverOwnerFQName?.isEmpty == false
    }.sorted {
        let left = entries[$0].compactRecord!.receiverOwnerFQName!
        let right = entries[$1].compactRecord!.receiverOwnerFQName!
        return left == right ? $0 < $1 : left < right
    }

    init?(data: Data) {
        if data.starts(with: CompactMetadataIndex.magic) {
            guard let parsed = CompactMetadataIndex.decode(data) else { return nil }
            metadataVersion = 3
            self.data = data
            bodyStart = parsed.bodyStart
            entries = parsed.entries
            return
        }
        let parsed = data.withUnsafeBytes { rawBytes -> (entries: [MetadataIndexEntry], bodyStart: Int)? in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            var cursor = 0
            func readLine() -> Range<Int>? {
                guard cursor < bytes.count else { return nil }
                var start = cursor
                while cursor < bytes.count, bytes[cursor] != 0x0A { cursor += 1 }
                var end = cursor
                if cursor < bytes.count { cursor += 1 }
                // Metadata uses ASCII separators, including CRLF on input.
                func isWhitespace(_ byte: UInt8) -> Bool {
                    byte == 0x20 || (0x09 ... 0x0D).contains(byte)
                }
                while start < end, isWhitespace(bytes[start]) { start += 1 }
                while end > start, isWhitespace(bytes[end - 1]) { end -= 1 }
                if start < end, bytes[start] >= 0x80 || bytes[end - 1] >= 0x80 {
                    let line = String(decoding: UnsafeBufferPointer(rebasing: bytes[start ..< end]), as: UTF8.self)
                    let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
                    if let first = line.rangeOfCharacter(from: nonWhitespace),
                       let last = line.rangeOfCharacter(from: nonWhitespace, options: .backwards)
                    {
                        start += line[..<first.lowerBound].utf8.count
                        end -= line[last.upperBound...].utf8.count
                    } else {
                        start = end
                    }
                }
                return start ..< end
            }
            func string(_ range: Range<Int>) -> String {
                String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
            }
            func recordLineHasCompleteInitializerInfo(_ recordBytes: UnsafeBufferPointer<UInt8>) -> Bool {
                var tokenStart = 0
                for index in 0 ... recordBytes.count
                where index == recordBytes.count || recordBytes[index] == 0x20 {
                    if tokenStart < index,
                       Self.stringMarkerMatches(tokenStart ..< index, bytes: recordBytes, marker: "initIndex=1")
                    {
                        return true
                    }
                    tokenStart = index + 1
                }
                return false
            }
            func headerLine() -> String? {
                readLine().map { string($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            guard headerLine() == "kklib-metadata-v2",
                  let recordsLine = headerLine(), recordsLine.hasPrefix("records="),
                  let recordCount = Int(recordsLine.dropFirst("records=".count)), recordCount >= 0,
                  headerLine() == "index"
            else { return nil }

            var entries: [MetadataIndexEntry] = []
            entries.reserveCapacity(min(recordCount, bytes.count / 8, 65_536))
            let decoder = MetadataDecoder()
            while let range = readLine() {
                if Self.stringMarkerMatches(range, bytes: bytes, marker: "body") {
                    return (entries, cursor)
                }
                if range.isEmpty, recordCount == 0 { continue }
                var firstTab = range.lowerBound
                while firstTab < range.upperBound, bytes[firstTab] != 0x09 { firstTab += 1 }
                guard firstTab < range.upperBound else { return nil }
                var secondTab = firstTab + 1
                while secondTab < range.upperBound, bytes[secondTab] != 0x09 { secondTab += 1 }
                guard secondTab < range.upperBound,
                      let offset = Int(string(range.lowerBound ..< firstTab)), offset >= 0,
                      let length = Int(string(firstTab + 1 ..< secondTab)), length > 0
                else { return nil }
                let recordBytes = UnsafeBufferPointer(rebasing: bytes[secondTab + 1 ..< range.upperBound])
                guard let record = decoder.decodeIndexRecordLine(recordBytes) else { return nil }
                entries.append(MetadataIndexEntry(
                    offset: offset, length: length, record: record,
                    hasCompleteInitializerInfo: recordLineHasCompleteInitializerInfo(recordBytes)
                ))
            }
            return nil
        }
        guard let parsed else { return nil }
        metadataVersion = 2
        self.data = data
        self.bodyStart = parsed.bodyStart
        self.entries = parsed.entries
    }

    private static func stringMarkerMatches(
        _ range: Range<Int>, bytes: UnsafeBufferPointer<UInt8>, marker: StaticString
    ) -> Bool {
        marker.withUTF8Buffer { bytes[range].elementsEqual($0) }
    }

    private static func shortName(_ fqName: String) -> Substring {
        fqName.lastIndex(of: ".").map { fqName[fqName.index(after: $0)...] } ?? Substring(fqName)
    }

    private func lowerBound<Key: Comparable>(
        in sortedIndices: [Int],
        key: Key,
        value: (Int) -> Key
    ) -> Int {
        var lower = 0
        var upper = sortedIndices.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if value(sortedIndices[middle]) < key {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    func fQNameRange(matching fqName: String) -> Range<Int> {
        let sorted = entriesSortedByFQName
        let lower = lowerBound(in: sorted, key: fqName) { entries[$0].fqName }
        var upper = lower
        while upper < sorted.count, entries[sorted[upper]].fqName == fqName {
            upper += 1
        }
        return lower ..< upper
    }

    func fQNamePrefixRange(_ prefix: String) -> Range<Int> {
        let sorted = entriesSortedByFQName
        let lower = lowerBound(in: sorted, key: prefix) { entries[$0].fqName }
        var upper = lower
        while upper < sorted.count, entries[sorted[upper]].fqName.hasPrefix(prefix) {
            upper += 1
        }
        return lower ..< upper
    }

    func entryIndex(sortedByFQNameAt position: Int) -> Int {
        entriesSortedByFQName[position]
    }

    func entryIndex(sortedByShortNameAt position: Int) -> Int {
        entriesSortedByShortName[position]
    }

    func shortNameRange(matching name: String) -> Range<Int> {
        let sorted = entriesSortedByShortName
        let lower = lowerBound(in: sorted, key: Substring(name)) { Self.shortName(entries[$0].fqName) }
        var upper = lower
        while upper < sorted.count, Self.shortName(entries[sorted[upper]].fqName) == Substring(name) {
            upper += 1
        }
        return lower ..< upper
    }

    func receiverOwnerRange(matching ownerFQName: String) -> Range<Int> {
        let sorted = entriesSortedByReceiverOwner
        let lower = lowerBound(in: sorted, key: ownerFQName) {
            entries[$0].compactRecord!.receiverOwnerFQName!
        }
        var upper = lower
        while upper < sorted.count,
              entries[sorted[upper]].compactRecord!.receiverOwnerFQName == ownerFQName
        {
            upper += 1
        }
        return lower ..< upper
    }

    func entryIndex(sortedByReceiverOwnerAt position: Int) -> Int {
        entriesSortedByReceiverOwner[position]
    }

    func nominalTypeParametersSignature(forFQName fqName: String) -> String? {
        for position in fQNameRange(matching: fqName) {
            let entry = entries[entryIndex(sortedByFQNameAt: position)]
            if let signature = entry.nominalTypeParametersSignature { return signature }
        }
        return nil
    }

    func record(for entry: MetadataIndexEntry) -> MetadataRecord? {
        guard entry.offset >= 0, entry.offset <= data.count - bodyStart,
              entry.length > 0, entry.length <= data.count - bodyStart - entry.offset
        else { return nil }
        if let cached = decodedRecords[entry.offset] {
            return cached
        }
        let start = bodyStart + entry.offset
        let end = start + entry.length
        let record = data.withUnsafeBytes { rawBytes -> MetadataRecord? in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            let line = UnsafeBufferPointer(rebasing: bytes[start ..< end])
            return MetadataDecoder().decodeIndexRecordLine(line)
        }
        if let record {
            decodedRecords[entry.offset] = record
        }
        return record
    }
}
