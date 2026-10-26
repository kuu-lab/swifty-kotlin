#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IndexedMetadataFileTests {
    @Test(arguments: [
        SymbolKind.package, .class, .interface, .object, .enumClass, .annotationClass,
        .typeAlias, .function, .constructor, .property, .field, .backingField,
        .typeParameter, .valueParameter, .local, .label,
    ])
    func encodedIndexMatchesLegacyDecoder(kind: SymbolKind) throws {
        let record = MetadataRecord(
            kind: kind, visibility: .protected, mangledName: "_KK_日本語", fqName: "demo.日本語",
            arity: 3, isSuspend: true, isInline: true, isOperator: true, isInfix: true,
            isOverride: true, isMemberExtension: true, receiverOwnerFQName: "demo.Owner",
            typeSignature: "F3<I,I,I,I>", defaultStubExternalLinkName: "default_call",
            externalLinkName: "external_call", companionObjectFQName: "demo.Owner.Companion",
            isDataClass: true, isOpenClass: true, modality: .abstract, isSealedClass: true,
            isFunInterface: true, isValueClass: true, isExpect: true, isActual: true,
            propertyReceiverTypeSignature: "Ldemo.Owner;", propertyGetterExternalLinkName: "getter",
            isMutable: true, nominalTypeParametersSignature: "Ldemo.Owner<O<T1>>;"
        )
        let encoder = MetadataEncoder()
        let encoded = encoder.serializeIndexed([record])
        let line = try #require(encoded.split(separator: "\n").first { $0.contains("\t") })
        let payload = try #require(line.split(separator: "\t", maxSplits: 2).last)
        let expected = try #require(MetadataDecoder().decode(String(payload)).first)
        let file = try #require(IndexedMetadataFile(data: Data(encoded.utf8)))
        let entry = try #require(file.entries.first)
        #expect(encoder.serialize([entry.record]) == encoder.serialize([expected]))
        #expect(entry.record.mangledName == expected.mangledName)
        #expect(entry.record.visibility == .protected)
        #expect(entry.record.receiverOwnerFQName == record.receiverOwnerFQName)
        #expect(entry.record.typeSignature == nil)
        #expect(encoder.serialize([try #require(file.record(for: entry))]) == encoder.serialize([record]))
    }

    @Test(arguments: [
        "function _ fq=demo.call arity=2 suspend=true inline=1 operator=true infix=true override=true memberExtension=true receiverFq=demo.Owner",
        "class _ fq=demo.C openClass=true modality=open companionFq=demo.C.Companion typeParamsSig=Ldemo.C<T1>;",
        "property _ fq=demo.p visibility=internal recv=Ldemo.C; getterLink=get mutable=true link=external",
        "function _ fq=old fq=demo.call arity=bad arity=7 visibility=unknown visibility=private schema=bad schema=v1 inline=1 inline=0",
        "function _ fq=demo.call arity=9223372036854775808 receiverFq= link= defaultLink= unknown=future",
        "class _ fq=demo.C fields=3 sig=I annotations=demo.Mark(a) valueUnderlying=I sealedSubs=demo.D",
        "class fq=demo.C",
        " \tclass _ fq=demo.C\t ",
        " \t\u{3000}class _ fq=demo.C\u{3000}\t ",
        "class _ fq=demo.C schema=v2",
        "unknown _ fq=demo.C",
        "class _ fq=",
    ])
    func compactParserPreservesLegacyFieldSemantics(line: String) {
        let expected = MetadataDecoder().decode(line).first
        let actual = Data(line.utf8).withUnsafeBytes {
            MetadataDecoder().decodeIndexRecordLine($0.bindMemory(to: UInt8.self))
        }
        #expect((actual == nil) == (expected == nil))
        if let actual, let expected {
            #expect(MetadataEncoder().serialize([actual]) == MetadataEncoder().serialize([expected]))
            #expect(actual.arity == expected.arity)
            #expect(actual.mangledName == expected.mangledName)
            #expect(actual.visibility == expected.visibility)
        }
    }

    @Test func readsCRLFAndUnicodeWithByteOffsetsAndSlicedData() throws {
        let body = "property _ fq=demo.日本語 sig=I\n"
        let prefix = " kklib-metadata-v2 \r\nrecords=1\r\nindex\r\n\u{3000}0\t\(body.utf8.count)\tproperty _ fq=demo.日本語\u{3000}\r\nbody\u{3000}\r\n"
        var data = Data("padding".utf8)
        data.append(Data((prefix + body).utf8))
        let file = try #require(IndexedMetadataFile(data: data.dropFirst(7)))
        let entry = try #require(file.entries.first)
        #expect(entry.record.fqName == "demo.日本語")
        #expect(try #require(file.record(for: entry)).typeSignature == "I")
    }

    @Test func emptyEncodedIndexIsReadable() throws {
        let file = try #require(IndexedMetadataFile(data: Data(MetadataEncoder().serializeIndexed([]).utf8)))
        #expect(file.entries.isEmpty)
    }

    @Test func unusedInvalidUTF8BodyRemainsLazy() throws {
        let first = "property _ fq=demo.日本語 sig=I\n"
        let prefix = "kklib-metadata-v2\nrecords=2\nindex\n0\t\(first.utf8.count)\tproperty _ fq=demo.日本語\n\(first.utf8.count)\t1\tclass _ fq=demo.Unused\nbody\n"
        var data = Data((prefix + first).utf8)
        data.append(0xFF)
        let file = try #require(IndexedMetadataFile(data: data))
        #expect(file.entries.count == 2)
        #expect(try #require(file.record(for: file.entries[0])).fqName == "demo.日本語")
        #expect(file.record(for: file.entries[1]) == nil)
        #expect(try #require(file.record(for: file.entries[0])).typeSignature == "I")
        #expect(file.record(for: MetadataIndexEntry(offset: 0, length: Int.max, record: file.entries[0].record)) == nil)
    }

    @Test(arguments: [
        "", "kklib-metadata-v2\n", "kklib-metadata-v2\nrecords=-1\nindex\nbody\n",
        "kklib-metadata-v2\nrecords=bad\nindex\nbody\n",
        "kklib-metadata-v2\nrecords=1\nindex\n0\t1\tclass _ fq=demo.C\n",
        "kklib-metadata-v2\nrecords=1\nindex\n-1\t1\tclass _ fq=demo.C\nbody\n",
        "kklib-metadata-v2\nrecords=1\nindex\n0\t0\tclass _ fq=demo.C\nbody\n",
        "kklib-metadata-v2\nrecords=1\nindex\n0\t1\tclass _ fq=demo.C schema=v2\nbody\n",
        "kklib-metadata-v2\nrecords=1\nindex\n0\t9223372036854775808\tclass _ fq=demo.C\nbody\n",
    ])
    func rejectsMalformedIndex(content: String) {
        #expect(IndexedMetadataFile(data: Data(content.utf8)) == nil)
    }

    @Test func outOfBoundsBodyRangesDoNotOverflow() throws {
        let content = "kklib-metadata-v2\nrecords=1\nindex\n\(Int.max)\t\(Int.max)\tclass _ fq=demo.C\nbody\nx"
        let file = try #require(IndexedMetadataFile(data: Data(content.utf8)))
        #expect(file.record(for: try #require(file.entries.first)) == nil)
        #expect(file.record(for: MetadataIndexEntry(offset: 0, length: Int.max, record: MetadataRecord(kind: .class))) == nil)
    }
}
#endif
