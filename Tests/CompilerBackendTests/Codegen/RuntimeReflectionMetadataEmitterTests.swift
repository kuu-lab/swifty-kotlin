@testable import CompilerCore
@testable import CompilerBackend
import XCTest

final class RuntimeReflectionMetadataEmitterTests: XCTestCase {

    func testSerializeEmptyRecordsProducesValidHeader() {
        let data = RuntimeReflectionMetadataEmitter.serialize([])
        // Header: magic(4) + version(4) + count(4) + strTableOffset(4) = 16
        // String table: entryCount(4) = 4
        XCTAssertEqual(data.count, 20)

        let decoded = RuntimeReflectionMetadataDecoder.decode(data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 0)
    }

    func testSerializeMagicAndVersion() {
        let data = RuntimeReflectionMetadataEmitter.serialize([])
        // Read magic bytes (little-endian serialized as 0x4D524B4B).
        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: magic), RuntimeReflectionMetadataEmitter.magic)

        // Read version
        let version = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: version), 1)
    }

    func testSerializeAndDecodeSingleClassRecord() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Foo__C__",
            fqName: "test.Foo",
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 5,
            superFQName: "test.Base",
            isDataClass: true
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)

        let r = decoded![0]
        XCTAssertEqual(r.kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.class))
        XCTAssertEqual(r.fqName, "test.Foo")
        XCTAssertEqual(r.simpleName, "Foo")
        XCTAssertEqual(r.superFqName, "test.Base")
        XCTAssertEqual(r.fieldCount, 3)
        XCTAssertEqual(r.instanceSizeWords, 5)

        // Flags: dataClass = bit 0
        XCTAssertEqual(r.flags & 0x01, 1)
    }

    func testSerializeAndDecodeSingleFunctionRecord() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__add__F__sig",
            fqName: "test.add",
            arity: 2,
            isSuspend: true,
            isInline: true,
            typeSignature: "F2<I,I,I>"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)

        let r = decoded![0]
        XCTAssertEqual(r.kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.function))
        XCTAssertEqual(r.fqName, "test.add")
        XCTAssertEqual(r.simpleName, "add")
        XCTAssertEqual(r.arity, 2)
        XCTAssertNil(r.superFqName)
        XCTAssertNil(r.fieldCount)
        XCTAssertNil(r.instanceSizeWords)

        // Flags: suspend = bit 3, inline = bit 4
        XCTAssertEqual(r.flags & (1 << 3), 1 << 3, "suspend flag should be set")
        XCTAssertEqual(r.flags & (1 << 4), 1 << 4, "inline flag should be set")
    }

    func testSerializeAndDecodeMultipleRecords() {
        let records = [
            MetadataRecord(kind: .class, mangledName: "m1", fqName: "pkg.ClassA", declaredFieldCount: 2),
            MetadataRecord(kind: .interface, mangledName: "m2", fqName: "pkg.IFace"),
            MetadataRecord(kind: .object, mangledName: "m3", fqName: "pkg.Companion"),
            MetadataRecord(kind: .function, mangledName: "m4", fqName: "pkg.greet", arity: 1),
        ]
        let data = RuntimeReflectionMetadataEmitter.serialize(records)
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 4)

        XCTAssertEqual(decoded?[0].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.class))
        XCTAssertEqual(decoded?[0].fqName, "pkg.ClassA")
        XCTAssertEqual(decoded?[0].fieldCount, 2)

        XCTAssertEqual(decoded?[1].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.interface))
        XCTAssertEqual(decoded?[1].fqName, "pkg.IFace")

        XCTAssertEqual(decoded?[2].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.object))
        XCTAssertEqual(decoded?[2].fqName, "pkg.Companion")

        XCTAssertEqual(decoded?[3].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.function))
        XCTAssertEqual(decoded?[3].fqName, "pkg.greet")
        XCTAssertEqual(decoded?[3].arity, 1)
    }

    func testFlagsBitEncoding() {
        // dataClass=1, sealedClass=1, valueClass=1, suspend=1, inline=1
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK",
            fqName: "test.AllFlags",
            isSuspend: true,
            isInline: true,
            isDataClass: true,
            isSealedClass: true,
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let flags = RuntimeReflectionMetadataEmitter.encodeFlags(record)
        XCTAssertEqual(flags & (1 << 0), 1 << 0, "dataClass bit")
        XCTAssertEqual(flags & (1 << 1), 1 << 1, "sealedClass bit")
        XCTAssertEqual(flags & (1 << 2), 1 << 2, "valueClass bit")
        XCTAssertEqual(flags & (1 << 3), 1 << 3, "suspend bit")
        XCTAssertEqual(flags & (1 << 4), 1 << 4, "inline bit")
    }

    func testFlagsAllZero() {
        let record = MetadataRecord(kind: .class, mangledName: "_KK", fqName: "test.Plain")
        let flags = RuntimeReflectionMetadataEmitter.encodeFlags(record)
        XCTAssertEqual(flags, 0)
    }

    func testKindOrdinalForAllKinds() {
        // Verify unique ordinals for all kinds.
        let allKinds: [SymbolKind] = [
            .package, .class, .interface, .object, .enumClass,
            .annotationClass, .typeAlias, .function, .constructor,
            .property, .field, .backingField, .typeParameter,
            .valueParameter, .local, .label,
        ]
        var ordinals = Set<UInt8>()
        for kind in allKinds {
            let ordinal = RuntimeReflectionMetadataEmitter.kindOrdinal(kind)
            XCTAssertFalse(ordinals.contains(ordinal), "Duplicate ordinal \(ordinal) for kind \(kind)")
            ordinals.insert(ordinal)
        }
        XCTAssertEqual(ordinals.count, allKinds.count)
    }

    func testStringTableDeduplicates() {
        // Two records with the same fqName should share a string table entry.
        let records = [
            MetadataRecord(kind: .class, mangledName: "m1", fqName: "test.Same"),
            MetadataRecord(kind: .interface, mangledName: "m2", fqName: "test.Same"),
        ]
        let data = RuntimeReflectionMetadataEmitter.serialize(records)
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?[0].fqName, "test.Same")
        XCTAssertEqual(decoded?[1].fqName, "test.Same")

        // Both should have the same simpleName.
        XCTAssertEqual(decoded?[0].simpleName, "Same")
        XCTAssertEqual(decoded?[1].simpleName, "Same")
    }

    func testOptionalFieldsSentinel() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            // No superFQName, fieldCount, instanceSizeWords
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)

        let r = decoded![0]
        XCTAssertNil(r.superFqName)
        XCTAssertNil(r.fieldCount)
        XCTAssertNil(r.instanceSizeWords)
    }

    func testRecordSizeIs24Bytes() {
        // Each record in the binary format should be exactly 24 bytes.
        XCTAssertEqual(RuntimeReflectionMetadataEmitter.recordSize, 24)
    }

    func testDataSizeWithOneRecord() {
        let record = MetadataRecord(kind: .class, mangledName: "m1", fqName: "test.Foo")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])

        // Header: 16 bytes
        // Records: 24 bytes
        // String table header: 4 bytes
        // Strings: "test.Foo" (4 + 8 = 12 bytes) + "Foo" (4 + 3 = 7 bytes)
        let expectedSize = 16 + 24 + 4 + 12 + 7
        XCTAssertEqual(data.count, expectedSize)
    }

    func testDecodeRejectsEmptyData() {
        let result = RuntimeReflectionMetadataDecoder.decode(Data())
        XCTAssertNil(result)
    }

    func testDecodeRejectsWrongMagic() {
        var data = Data(count: 20)
        // Wrong magic
        data[0] = 0x00
        data[1] = 0x00
        data[2] = 0x00
        data[3] = 0x00
        let result = RuntimeReflectionMetadataDecoder.decode(data)
        XCTAssertNil(result)
    }

    func testDecodeRejectsWrongVersion() {
        var data = RuntimeReflectionMetadataEmitter.serialize([])
        // Overwrite version field with 99
        let versionOffset = 4
        data[versionOffset] = 99
        data[versionOffset + 1] = 0
        data[versionOffset + 2] = 0
        data[versionOffset + 3] = 0
        let result = RuntimeReflectionMetadataDecoder.decode(data)
        XCTAssertNil(result)
    }

    func testSimpleNameExtractionFromFQName() {
        let record = MetadataRecord(kind: .class, mangledName: "m1", fqName: "com.example.pkg.MyClass")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertEqual(decoded?[0].simpleName, "MyClass")
        XCTAssertEqual(decoded?[0].fqName, "com.example.pkg.MyClass")
    }

    func testSimpleNameForTopLevelFunction() {
        let record = MetadataRecord(kind: .function, mangledName: "m1", fqName: "main")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        // When there's no dot, simpleName == fqName.
        XCTAssertEqual(decoded?[0].simpleName, "main")
        XCTAssertEqual(decoded?[0].fqName, "main")
    }

    func testSealedClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK",
            fqName: "test.Shape",
            isSealedClass: true,
            sealedSubclassFQNames: ["test.Circle", "test.Rect"]
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        let sealedFlags = decoded![0].flags
        XCTAssertEqual(sealedFlags & (1 << 1), 1 << 1, "sealed bit should be set")
    }

    func testValueClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_KK",
            fqName: "test.Wrapper",
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        let valueFlags = decoded![0].flags
        XCTAssertEqual(valueFlags & (1 << 2), 1 << 2, "valueClass bit should be set")
    }

    func testArityClampedToU16Max() {
        // Arity larger than UInt16.max should be clamped.
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.manyParams",
            arity: 100_000
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?[0].arity, UInt16.max)
    }

    func testEnumClassKindOrdinal() {
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_KK",
            fqName: "test.Color",
            declaredFieldCount: 3
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?[0].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.enumClass))
        XCTAssertEqual(decoded?[0].fieldCount, 3)
    }

    func testAnnotationClassKindOrdinal() {
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_KK",
            fqName: "test.MyAnnotation"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?[0].kindOrdinal, RuntimeReflectionMetadataEmitter.kindOrdinal(.annotationClass))
    }
}

private struct RuntimeReflectionMetadataDecoder {
    struct DecodedRecord {
        let kindOrdinal: UInt8
        let flags: UInt8
        let arity: UInt16
        let fqName: String
        let simpleName: String
        let superFqName: String?
        let fieldCount: UInt32?
        let instanceSizeWords: UInt32?
    }

    static func decode(_ data: Data) -> [DecodedRecord]? {
        guard data.count >= 16 else { return nil }
        var offset = 0

        let magic = readU32(data, at: &offset)
        guard magic == RuntimeReflectionMetadataEmitter.magic else { return nil }

        let version = readU32(data, at: &offset)
        guard version == RuntimeReflectionMetadataEmitter.version else { return nil }

        let recordCount = readU32(data, at: &offset)
        let stringTableOffset = readU32(data, at: &offset)
        let recordSize = UInt64(RuntimeReflectionMetadataEmitter.recordSize)
        let recordsSizeInBytes = UInt64(recordCount) * recordSize
        guard recordsSizeInBytes <= UInt64(Int.max) else { return nil }
        let recordsSize = Int(recordsSizeInBytes)
        let recordBytesEnd = 16 + recordsSize

        let stringTableOffsetInt = Int(stringTableOffset)
        guard stringTableOffsetInt <= data.count,
              stringTableOffsetInt >= recordBytesEnd
        else { return nil }

        guard let strings = decodeStringTable(data, at: stringTableOffsetInt) else {
            return nil
        }

        var records: [DecodedRecord] = []
        let recordIterations = Int(recordCount)
        for _ in 0..<recordIterations {
            guard offset + RuntimeReflectionMetadataEmitter.recordSize <= data.count else {
                return nil
            }
            let kind = data[offset]; offset += 1
            let flags = data[offset]; offset += 1
            let arity = readU16(data, at: &offset)
            let fqNameIdx = readU32(data, at: &offset)
            let simpleNameIdx = readU32(data, at: &offset)
            let superFqNameIdx = readU32(data, at: &offset)
            let fieldCountRaw = readU32(data, at: &offset)
            let instanceSizeRaw = readU32(data, at: &offset)

            guard Int(fqNameIdx) < strings.count, Int(simpleNameIdx) < strings.count else {
                return nil
            }
            let fqName = strings[Int(fqNameIdx)]
            let simpleName = strings[Int(simpleNameIdx)]
            let superFqName: String?
            if superFqNameIdx == RuntimeReflectionMetadataEmitter.sentinel {
                superFqName = nil
            } else {
                guard Int(superFqNameIdx) < strings.count else {
                    return nil
                }
                superFqName = strings[Int(superFqNameIdx)]
            }
            let fieldCount: UInt32? = fieldCountRaw == RuntimeReflectionMetadataEmitter.sentinel ? nil : fieldCountRaw
            let instanceSize: UInt32? = instanceSizeRaw == RuntimeReflectionMetadataEmitter.sentinel ? nil : instanceSizeRaw

            records.append(DecodedRecord(
                kindOrdinal: kind,
                flags: flags,
                arity: arity,
                fqName: fqName,
                simpleName: simpleName,
                superFqName: superFqName,
                fieldCount: fieldCount,
                instanceSizeWords: instanceSize
            ))
        }
        return records
    }

    private static func decodeStringTable(_ data: Data, at startOffset: Int) -> [String]? {
        var offset = startOffset
        guard offset + 4 <= data.count else { return nil }

        let count = readU32(data, at: &offset)
        var strings: [String] = []
        strings.reserveCapacity(Int(count))

        for _ in 0..<count {
            guard offset + 4 <= data.count else { return nil }
            let length = readU32(data, at: &offset)
            let endIdx = offset + Int(length)
            guard endIdx <= data.count else { return nil }
            let stringData = data[offset..<endIdx]
            let string = String(decoding: stringData, as: UTF8.self)
            guard stringData.elementsEqual(string.utf8) else { return nil }
            strings.append(string)
            offset = endIdx
        }
        return strings
    }

    private static func readU16(_ data: Data, at offset: inout Int) -> UInt16 {
        guard offset + 2 <= data.count else {
            offset += 2
            return 0
        }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        offset += 2
        return b0 | (b1 << 8)
    }

    private static func readU32(_ data: Data, at offset: inout Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            offset += 4
            return 0
        }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        offset += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
