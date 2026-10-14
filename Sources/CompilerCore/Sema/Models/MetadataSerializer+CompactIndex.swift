import Foundation

/// Shell-only shape. Full signatures, layouts, contracts and annotations stay
/// in the independently addressed body and are never constructed during v3 decode.
struct CompactMetadataIndexRecord {
    let kind: SymbolKind
    let visibility: Visibility
    let arity: Int
    let flags: UInt32
    let fqName: String
    let mangledName: String
    let receiverOwnerFQName: String?
    let defaultStubExternalLinkName: String?
    let externalLinkName: String?
    let propertyReceiverTypeSignature: String?
    let propertyGetterExternalLinkName: String?
    let nominalTypeParametersSignature: String?
    let companionObjectFQName: String?
    let objectInitializerLinkName: String?
    let companionInitializerLinkName: String?
    let enumStaticInitLinkName: String?
    var isSuspend: Bool { flags & (1 << 0) != 0 }
    var isInline: Bool { flags & (1 << 1) != 0 }
    var isOperator: Bool { flags & (1 << 2) != 0 }
    var isInfix: Bool { flags & (1 << 3) != 0 }
    var isOverride: Bool { flags & (1 << 4) != 0 }
    var isMemberExtension: Bool { flags & (1 << 5) != 0 }
    var isMutable: Bool { flags & (1 << 6) != 0 }
    var isDataClass: Bool { flags & (1 << 7) != 0 }
    var isOpenClass: Bool { flags & (1 << 8) != 0 }
    var isInnerClass: Bool { flags & (1 << 9) != 0 }
    var isSealedClass: Bool { flags & (1 << 10) != 0 }
    var isFunInterface: Bool { flags & (1 << 11) != 0 }
    var isValueClass: Bool { flags & (1 << 12) != 0 }
    var isExpect: Bool { flags & (1 << 13) != 0 }
    var isActual: Bool { flags & (1 << 14) != 0 }
    var hasCompleteInitializerInfo: Bool { flags & (1 << 15) != 0 }
    var propertySetterVisibility: Visibility? {
        let id = Int((flags >> 18) & 7)
        return id == 0 ? nil : CompactMetadataIndex.visibilities[id - 1]
    }
    var modality: MetadataModality {
        switch (flags >> 16) & 3 {
        case 1: .open
        case 2: .abstract
        default: .final
        }
    }

    /// Compatibility view for tests and legacy callers; the importer uses the
    /// shell shape directly, without allocating a generic MetadataRecord.
    var record: MetadataRecord {
        MetadataRecord(
            kind: kind, visibility: visibility, mangledName: mangledName, fqName: fqName,
            arity: arity,
            isSuspend: isSuspend,
            isInline: isInline,
            isOperator: isOperator,
            isInfix: isInfix,
            isOverride: isOverride,
            isMemberExtension: isMemberExtension,
            receiverOwnerFQName: receiverOwnerFQName,
            defaultStubExternalLinkName: defaultStubExternalLinkName,
            externalLinkName: externalLinkName,
            companionObjectFQName: companionObjectFQName,
            objectInitializerLinkName: objectInitializerLinkName,
            companionInitializerLinkName: companionInitializerLinkName,
            enumStaticInitLinkName: enumStaticInitLinkName,
            isDataClass: isDataClass,
            isOpenClass: isOpenClass,
            isInnerClass: isInnerClass,
            modality: modality,
            isSealedClass: isSealedClass,
            isFunInterface: isFunInterface,
            isValueClass: isValueClass,
            isExpect: isExpect,
            isActual: isActual,
            propertyReceiverTypeSignature: propertyReceiverTypeSignature,
            propertyGetterExternalLinkName: propertyGetterExternalLinkName,
            propertySetterVisibility: propertySetterVisibility,
            isMutable: isMutable,
            nominalTypeParametersSignature: nominalTypeParametersSignature
        )
    }
}

/// v3 uses little-endian integers, a shared UTF-8 string table, and 80-byte
/// entries. IDs are explicit wire values, independent of Swift enum raw values.
enum CompactMetadataIndex {
    static let magic = Data("kklib-metadata-v3\n".utf8)
    static let entrySize = 80
    static let kinds: [SymbolKind] = [
        .package, .class, .interface, .object, .enumClass, .annotationClass,
        .typeAlias, .function, .constructor, .property, .field, .backingField,
        .typeParameter, .valueParameter, .local, .label,
    ]
    static let visibilities: [Visibility] = [.public, .private, .internal, .protected]

    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func decode(_ data: Data) -> (entries: [MetadataIndexEntry], bodyStart: Int)? {
        data.withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            var cursor = magic.count
            func integer<T: FixedWidthInteger>(_ type: T.Type) -> T? {
                guard cursor <= bytes.count, MemoryLayout<T>.size <= bytes.count - cursor else { return nil }
                let value = rawBytes.loadUnaligned(fromByteOffset: cursor, as: T.self)
                cursor += MemoryLayout<T>.size
                return T(littleEndian: value)
            }
            guard data.starts(with: magic),
                  let countValue = integer(UInt32.self),
                  let stringsValue = integer(UInt32.self),
                  let stringBytesValue = integer(UInt32.self),
                  let width = integer(UInt32.self), width == entrySize
            else { return nil }
            let count = Int(countValue)
            let stringCount = Int(stringsValue)
            let stringBytes = Int(stringBytesValue)
            guard stringBytes <= bytes.count - cursor,
                  stringCount > 0, stringCount <= stringBytes / 4,
                  count <= (bytes.count - cursor - stringBytes) / entrySize
            else { return nil }
            let stringsEnd = cursor + stringBytes
            let bodyStart = stringsEnd + count * entrySize
            var strings: [String] = []
            strings.reserveCapacity(stringCount)
            for _ in 0 ..< stringCount {
                guard cursor <= stringsEnd - 4,
                      let lengthValue = integer(UInt32.self),
                      Int(lengthValue) <= stringsEnd - cursor
                else { return nil }
                let end = cursor + Int(lengthValue)
                guard let string = String(bytes: bytes[cursor ..< end], encoding: .utf8) else { return nil }
                strings.append(string)
                cursor = end
            }
            guard cursor == stringsEnd, strings[0].isEmpty else { return nil }
            var entries: [MetadataIndexEntry] = []
            entries.reserveCapacity(count)
            for _ in 0 ..< count {
                guard let offsetValue = integer(UInt64.self),
                      let lengthValue = integer(UInt64.self),
                      let arityValue = integer(UInt32.self),
                      let flags = integer(UInt32.self), flags >> 21 == 0, ((flags >> 16) & 3) != 3,
                      ((flags >> 18) & 7) <= 4,
                      let kindID = integer(UInt32.self), kindID < kinds.count,
                      let visibilityID = integer(UInt32.self), visibilityID < visibilities.count,
                      offsetValue <= UInt64(bytes.count - bodyStart), lengthValue > 0,
                      lengthValue <= UInt64(bytes.count - bodyStart) - offsetValue
                else { return nil }
                // Fixed field positions avoid token/key parsing and per-field
                // string allocation. Shared IDs also preserve Unicode names.
                let idsStart = cursor
                for _ in 0 ..< 12 {
                    guard let id = integer(UInt32.self), id < strings.count else { return nil }
                }
                func string(_ field: Int) -> String {
                    let id = UInt32(littleEndian: rawBytes.loadUnaligned(fromByteOffset: idsStart + field * 4, as: UInt32.self))
                    return strings[Int(id)]
                }
                func optionalString(_ field: Int) -> String? {
                    let id = UInt32(littleEndian: rawBytes.loadUnaligned(fromByteOffset: idsStart + field * 4, as: UInt32.self))
                    return id == 0 ? nil : strings[Int(id)]
                }
                guard !string(0).isEmpty else { return nil }
                let record = CompactMetadataIndexRecord(
                    kind: kinds[Int(kindID)], visibility: visibilities[Int(visibilityID)],
                    arity: Int(arityValue), flags: flags,
                    fqName: string(0),
                    mangledName: string(1),
                    receiverOwnerFQName: optionalString(2),
                    defaultStubExternalLinkName: optionalString(3),
                    externalLinkName: optionalString(4),
                    propertyReceiverTypeSignature: optionalString(5),
                    propertyGetterExternalLinkName: optionalString(6),
                    nominalTypeParametersSignature: optionalString(7),
                    companionObjectFQName: optionalString(8),
                    objectInitializerLinkName: optionalString(9),
                    companionInitializerLinkName: optionalString(10),
                    enumStaticInitLinkName: optionalString(11)
                )
                entries.append(MetadataIndexEntry(
                    offset: Int(offsetValue), length: Int(lengthValue), compactRecord: record
                ))
            }
            return (entries, bodyStart)
        }
    }
}

extension MetadataEncoder {
    /// Producer-side work replaces every consumer's eager text-index decode.
    package func serializeCompactIndexed(_ records: [MetadataRecord]) -> Data {
        let lines = serialize(records).split(whereSeparator: \.isNewline).dropFirst()
        var body = Data()
        var table = Data()
        var stringData = Data()
        var ids: [String: UInt32] = [:]
        func intern(_ value: String?) -> UInt32 {
            guard let value else { return 0 }
            if let id = ids[value] { return id }
            let id = UInt32(ids.count)
            ids[value] = id
            let bytes = Data(value.utf8)
            CompactMetadataIndex.append(UInt32(bytes.count), to: &stringData)
            stringData.append(bytes)
            return id
        }
        _ = intern("")
        for (record, line) in zip(records, lines) {
            let callable = record.kind == .function || record.kind == .constructor
            let property = record.kind == .property || record.kind == .field
            let nominal = Self.nominalKinds.contains(record.kind)
            var flags: UInt32 = 0
            if callable && record.isSuspend { flags |= 1 << 0 }
            if callable && record.isInline { flags |= 1 << 1 }
            if callable && record.isOperator { flags |= 1 << 2 }
            if callable && record.isInfix { flags |= 1 << 3 }
            if callable && record.isOverride { flags |= 1 << 4 }
            if record.isMemberExtension { flags |= 1 << 5 }
            if property && record.isMutable { flags |= 1 << 6 }
            if record.isDataClass { flags |= 1 << 7 }
            if record.isOpenClass { flags |= 1 << 8 }
            if record.isInnerClass { flags |= 1 << 9 }
            if record.isSealedClass { flags |= 1 << 10 }
            if record.isFunInterface { flags |= 1 << 11 }
            if record.isValueClass { flags |= 1 << 12 }
            if record.isExpect { flags |= 1 << 13 }
            if record.isActual { flags |= 1 << 14 }
            if nominal { flags |= 1 << 15 }
            if record.modality == .open { flags |= 1 << 16 }
            if record.modality == .abstract { flags |= 2 << 16 }
            if property, let visibility = record.propertySetterVisibility {
                let id = CompactMetadataIndex.visibilities.firstIndex(of: visibility)! + 1
                flags |= UInt32(id) << 18
            }
            let bodyLine = Data((line + "\n").utf8)
            CompactMetadataIndex.append(UInt64(body.count), to: &table)
            CompactMetadataIndex.append(UInt64(bodyLine.count), to: &table)
            CompactMetadataIndex.append(UInt32(callable ? record.arity : 0), to: &table)
            CompactMetadataIndex.append(flags, to: &table)
            CompactMetadataIndex.append(UInt32(CompactMetadataIndex.kinds.firstIndex(of: record.kind)!), to: &table)
            CompactMetadataIndex.append(UInt32(CompactMetadataIndex.visibilities.firstIndex(of: record.visibility)!), to: &table)
            CompactMetadataIndex.append(intern(record.fqName), to: &table)
            CompactMetadataIndex.append(intern(record.mangledName), to: &table)
            CompactMetadataIndex.append(intern((record.receiverOwnerFQName).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern((callable ? record.defaultStubExternalLinkName : nil).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern((record.externalLinkName).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern(property ? record.propertyReceiverTypeSignature : nil), to: &table)
            CompactMetadataIndex.append(intern((property ? record.propertyGetterExternalLinkName : nil).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern(nominal ? record.nominalTypeParametersSignature : nil), to: &table)
            CompactMetadataIndex.append(intern((nominal ? record.companionObjectFQName : nil).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern((nominal ? record.objectInitializerLinkName : nil).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern((nominal ? record.companionInitializerLinkName : nil).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            CompactMetadataIndex.append(intern((nominal ? record.enumStaticInitLinkName : nil).flatMap { $0.isEmpty ? nil : $0 }), to: &table)
            body.append(bodyLine)
        }
        var result = CompactMetadataIndex.magic
        CompactMetadataIndex.append(UInt32(records.count), to: &result)
        CompactMetadataIndex.append(UInt32(ids.count), to: &result)
        CompactMetadataIndex.append(UInt32(stringData.count), to: &result)
        CompactMetadataIndex.append(UInt32(CompactMetadataIndex.entrySize), to: &result)
        result.append(stringData)
        result.append(table)
        result.append(body)
        return result
    }

    /// Cache integrity checks need only the compact shell's inline routing.
    package static func compactInlineKIRMangledNames(in data: Data) -> [String]? {
        guard data.starts(with: CompactMetadataIndex.magic), let file = IndexedMetadataFile(data: data) else { return nil }
        return file.entries.compactMap { entry in
            guard let record = entry.compactRecord, record.isInline else { return nil }
            return record.mangledName
        }
    }
}
