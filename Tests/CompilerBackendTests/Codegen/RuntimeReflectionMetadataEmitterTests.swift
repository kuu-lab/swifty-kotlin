#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct RuntimeReflectionMetadataEmitterTests {

    @Test
    func testSerializeEmptyRecordsProducesValidHeader() {
        let data = RuntimeReflectionMetadataEmitter.serialize([])
        // Header: magic(4) + version(4) + count(4) + strTableOffset(4) = 16
        // String table: entryCount(4) = 4
        #expect(data.count == 20)

        let decoded = RuntimeReflectionMetadataDecoder.decode(data)
        #expect(decoded != nil)
        #expect(decoded?.count == 0)
    }

    @Test
    func testSerializeMagicAndVersion() {
        let data = RuntimeReflectionMetadataEmitter.serialize([])
        // Read magic bytes (little-endian serialized as 0x4D524B4B).
        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        #expect(UInt32(littleEndian: magic) == RuntimeReflectionMetadataEmitter.magic)

        // Read version
        let version = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        #expect(UInt32(littleEndian: version) == 1)
    }

    @Test
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

        #expect(decoded != nil)
        #expect(decoded?.count == 1)

        let r = decoded![0]
        #expect(r.kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.class))
        #expect(r.fqName == "test.Foo")
        #expect(r.simpleName == "Foo")
        #expect(r.superFqName == "test.Base")
        #expect(r.fieldCount == 3)
        #expect(r.instanceSizeWords == 5)

        // Flags: dataClass = bit 0
        #expect(r.flags & 0x01 == 1)
    }

    @Test
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

        #expect(decoded != nil)
        #expect(decoded?.count == 1)

        let r = decoded![0]
        #expect(r.kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.function))
        #expect(r.fqName == "test.add")
        #expect(r.simpleName == "add")
        #expect(r.arity == 2)
        #expect(r.superFqName == nil)
        #expect(r.fieldCount == nil)
        #expect(r.instanceSizeWords == nil)

        // Flags: suspend = bit 3, inline = bit 4
        #expect(r.flags & (1 << 3) == 1 << 3, "suspend flag should be set")
        #expect(r.flags & (1 << 4) == 1 << 4, "inline flag should be set")
    }

    @Test
    func testSerializeAndDecodeMultipleRecords() {
        let records = [
            MetadataRecord(kind: .class, mangledName: "m1", fqName: "pkg.ClassA", declaredFieldCount: 2),
            MetadataRecord(kind: .interface, mangledName: "m2", fqName: "pkg.IFace"),
            MetadataRecord(kind: .object, mangledName: "m3", fqName: "pkg.Companion"),
            MetadataRecord(kind: .function, mangledName: "m4", fqName: "pkg.greet", arity: 1),
        ]
        let data = RuntimeReflectionMetadataEmitter.serialize(records)
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        #expect(decoded != nil)
        #expect(decoded?.count == 4)

        #expect(decoded?[0].kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.class))
        #expect(decoded?[0].fqName == "pkg.ClassA")
        #expect(decoded?[0].fieldCount == 2)

        #expect(decoded?[1].kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.interface))
        #expect(decoded?[1].fqName == "pkg.IFace")

        #expect(decoded?[2].kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.object))
        #expect(decoded?[2].fqName == "pkg.Companion")

        #expect(decoded?[3].kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.function))
        #expect(decoded?[3].fqName == "pkg.greet")
        #expect(decoded?[3].arity == 1)
    }

    @Test
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
        #expect(flags & (1 << 0) == 1 << 0, "dataClass bit")
        #expect(flags & (1 << 1) == 1 << 1, "sealedClass bit")
        #expect(flags & (1 << 2) == 1 << 2, "valueClass bit")
        #expect(flags & (1 << 3) == 1 << 3, "suspend bit")
        #expect(flags & (1 << 4) == 1 << 4, "inline bit")
    }

    @Test
    func testFlagsAllZero() {
        let record = MetadataRecord(kind: .class, mangledName: "_KK", fqName: "test.Plain")
        let flags = RuntimeReflectionMetadataEmitter.encodeFlags(record)
        #expect(flags == 0)
    }

    @Test
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
            #expect(!ordinals.contains(ordinal), "Duplicate ordinal \(ordinal) for kind \(kind)")
            ordinals.insert(ordinal)
        }
        #expect(ordinals.count == allKinds.count)
    }

    @Test
    func testStringTableDeduplicates() {
        // Two records with the same fqName should share a string table entry.
        let records = [
            MetadataRecord(kind: .class, mangledName: "m1", fqName: "test.Same"),
            MetadataRecord(kind: .interface, mangledName: "m2", fqName: "test.Same"),
        ]
        let data = RuntimeReflectionMetadataEmitter.serialize(records)
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        #expect(decoded != nil)
        #expect(decoded?.count == 2)
        #expect(decoded?[0].fqName == "test.Same")
        #expect(decoded?[1].fqName == "test.Same")

        // Both should have the same simpleName.
        #expect(decoded?[0].simpleName == "Same")
        #expect(decoded?[1].simpleName == "Same")
    }

    @Test
    func testOptionalFieldsSentinel() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            // No superFQName, fieldCount, instanceSizeWords
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        #expect(decoded != nil)
        #expect(decoded?.count == 1)

        let r = decoded![0]
        #expect(r.superFqName == nil)
        #expect(r.fieldCount == nil)
        #expect(r.instanceSizeWords == nil)
    }

    @Test
    func testRecordSizeIs24Bytes() {
        // Each record in the binary format should be exactly 24 bytes.
        #expect(RuntimeReflectionMetadataEmitter.recordSize == 24)
    }

    @Test
    func testDataSizeWithOneRecord() {
        let record = MetadataRecord(kind: .class, mangledName: "m1", fqName: "test.Foo")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])

        // Header: 16 bytes
        // Records: 24 bytes
        // String table header: 4 bytes
        // Strings: "test.Foo" (4 + 8 = 12 bytes) + "Foo" (4 + 3 = 7 bytes)
        let expectedSize = 16 + 24 + 4 + 12 + 7
        #expect(data.count == expectedSize)
    }

    @Test
    func testDecodeRejectsEmptyData() {
        let result = RuntimeReflectionMetadataDecoder.decode(Data())
        #expect(result == nil)
    }

    @Test
    func testDecodeRejectsWrongMagic() {
        var data = Data(count: 20)
        // Wrong magic
        data[0] = 0x00
        data[1] = 0x00
        data[2] = 0x00
        data[3] = 0x00
        let result = RuntimeReflectionMetadataDecoder.decode(data)
        #expect(result == nil)
    }

    @Test
    func testDecodeRejectsWrongVersion() {
        var data = RuntimeReflectionMetadataEmitter.serialize([])
        // Overwrite version field with 99
        let versionOffset = 4
        data[versionOffset] = 99
        data[versionOffset + 1] = 0
        data[versionOffset + 2] = 0
        data[versionOffset + 3] = 0
        let result = RuntimeReflectionMetadataDecoder.decode(data)
        #expect(result == nil)
    }

    @Test
    func testSimpleNameExtractionFromFQName() {
        let record = MetadataRecord(kind: .class, mangledName: "m1", fqName: "com.example.pkg.MyClass")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        #expect(decoded?[0].simpleName == "MyClass")
        #expect(decoded?[0].fqName == "com.example.pkg.MyClass")
    }

    @Test
    func testSimpleNameForTopLevelFunction() {
        let record = MetadataRecord(kind: .function, mangledName: "m1", fqName: "main")
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        // When there's no dot, simpleName == fqName.
        #expect(decoded?[0].simpleName == "main")
        #expect(decoded?[0].fqName == "main")
    }

    @Test
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

        #expect(decoded != nil)
        let sealedFlags = decoded![0].flags
        #expect(sealedFlags & (1 << 1) == 1 << 1, "sealed bit should be set")
    }

    @Test
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

        #expect(decoded != nil)
        let valueFlags = decoded![0].flags
        #expect(valueFlags & (1 << 2) == 1 << 2, "valueClass bit should be set")
    }

    @Test
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

        #expect(decoded != nil)
        #expect(decoded?[0].arity == UInt16.max)
    }

    @Test
    func testEnumClassKindOrdinal() {
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_KK",
            fqName: "test.Color",
            declaredFieldCount: 3
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        #expect(decoded != nil)
        #expect(decoded?[0].kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.enumClass))
        #expect(decoded?[0].fieldCount == 3)
    }

    @Test
    func testAnnotationClassKindOrdinal() {
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_KK",
            fqName: "test.MyAnnotation"
        )
        let data = RuntimeReflectionMetadataEmitter.serialize([record])
        let decoded = RuntimeReflectionMetadataDecoder.decode(data)

        #expect(decoded != nil)
        #expect(decoded?[0].kindOrdinal == RuntimeReflectionMetadataEmitter.kindOrdinal(.annotationClass))
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
#endif
