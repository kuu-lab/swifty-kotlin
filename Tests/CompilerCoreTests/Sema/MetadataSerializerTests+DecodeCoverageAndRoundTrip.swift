#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension MetadataSerializerTests {
    @Test func testDecodeDataClassFlag() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Data schema=v1 dataClass=1\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].isDataClass)
    }

    @Test func testDecodeSealedClassWithSubs() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Sealed schema=v1 sealedClass=1 sealedSubs=test.SubA,test.SubB\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].isSealedClass)
        #expect(records[0].sealedSubclassFQNames == ["test.SubA", "test.SubB"])
    }

    @Test func testDecodeValueClass() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nclass _KK fq=test.Wrapper schema=v1 valueClass=1 valueUnderlying=I\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].isValueClass)
        #expect(records[0].valueClassUnderlyingTypeSig == "I")
    }

    @Test func testDecodeConstructorWithLink() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nconstructor _KK fq=test.Foo.init schema=v1 arity=1 suspend=0 inline=0 sig=F1<I,U> link=Foo_init\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].kind == .constructor)
        #expect(records[0].externalLinkName == "Foo_init")
    }

    @Test func testDecodePropertyWithSig() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nproperty _KK fq=test.x schema=v1 sig=I\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].kind == .property)
        #expect(records[0].typeSignature == "I")
    }

    @Test func testDecodeEmptyContent() {
        let decoder = MetadataDecoder()
        let records = decoder.decode("")
        #expect(records.isEmpty)
    }

    @Test func testDecodeOnlySymbolsHeader() {
        let decoder = MetadataDecoder()
        let records = decoder.decode("symbols=0\n")
        #expect(records.isEmpty)
    }

    @Test func testDecodeSkipsLinesWithoutFQ() {
        let decoder = MetadataDecoder()
        // A line without fq= should be skipped
        let content = "symbols=1\nfunction _KK arity=2\n"
        let records = decoder.decode(content)
        #expect(records.isEmpty)
    }

    @Test func testDecodeSkipsUnknownKind() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nunknownKind _KK fq=test.fn schema=v1\n"
        let records = decoder.decode(content)
        #expect(records.isEmpty)
    }

    @Test func testDecodeMultipleRecords() {
        let decoder = MetadataDecoder()
        let content = """
        symbols=2
        function _KK1 fq=test.fn1 schema=v1 arity=0 suspend=0 inline=0
        class _KK2 fq=test.Cls schema=v1
        """
        let records = decoder.decode(content)
        #expect(records.count == 2)
        #expect(records[0].kind == .function)
        #expect(records[1].kind == .class)
    }

    // MARK: - Encode/Decode round-trip

    @Test func testSerializeDeserializeRoundTripFunction() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__add__F__sig",
            fqName: "test.add",
            arity: 2,
            isSuspend: true,
            isInline: true,
            typeSignature: "F2<I,I,I>"
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == original.kind)
        #expect(decoded[0].fqName == original.fqName)
        #expect(decoded[0].arity == original.arity)
        #expect(decoded[0].isSuspend == original.isSuspend)
        #expect(decoded[0].isInline == original.isInline)
        #expect(decoded[0].typeSignature == original.typeSignature)
    }

    @Test func testSerializeDeserializeRoundTripClassWithLayout() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__Foo__C__",
            fqName: "test.Foo",
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 3,
            declaredItableSize: 1,
            superFQName: "test.Base",
            isDataClass: true,
            isSealedClass: true,
            sealedSubclassFQNames: ["test.SubA"]
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "test.Foo")
        #expect(decoded[0].declaredFieldCount == 2)
        #expect(decoded[0].declaredInstanceSizeWords == 4)
        #expect(decoded[0].declaredVtableSize == 3)
        #expect(decoded[0].declaredItableSize == 1)
        #expect(decoded[0].superFQName == "test.Base")
        #expect(decoded[0].isDataClass)
        #expect(decoded[0].isSealedClass)
        #expect(decoded[0].sealedSubclassFQNames == ["test.SubA"])
    }

    @Test func testSerializeDeserializeRoundTripValueClass() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .class,
            mangledName: "_KK_test__W__C__",
            fqName: "test.W",
            isValueClass: true,
            valueClassUnderlyingTypeSig: "I"
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].isValueClass)
        #expect(decoded[0].valueClassUnderlyingTypeSig == "I")
    }

    @Test func testSerializeDeserializeRoundTripAnnotations() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let original = MetadataRecord(
            kind: .function,
            mangledName: "_KK_test__fn__F__",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["Use newFn"],
                    useSiteTarget: "get"
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.JvmStatic"
                ),
            ]
        )
        let serialized = encoder.serialize([original])
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 2)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Deprecated")
        #expect(decoded[0].annotations[0].arguments == ["Use newFn"])
        #expect(decoded[0].annotations[0].useSiteTarget == "get")
        #expect(decoded[0].annotations[1].annotationFQName == "kotlin.JvmStatic")
    }

    @Test func testSerializeDeserializeRoundTripMultipleRecords() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let records = [
            MetadataRecord(kind: .function, mangledName: "m1", fqName: "test.fn1", arity: 0),
            MetadataRecord(kind: .class, mangledName: "m2", fqName: "test.Cls"),
            MetadataRecord(kind: .interface, mangledName: "m3", fqName: "test.IFace"),
            MetadataRecord(kind: .property, mangledName: "m4", fqName: "test.prop", typeSignature: "I"),
            MetadataRecord(kind: .object, mangledName: "m5", fqName: "test.Obj"),
        ]
        let serialized = encoder.serialize(records)
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 5)
        #expect(decoded[0].kind == .function)
        #expect(decoded[1].kind == .class)
        #expect(decoded[2].kind == .interface)
        #expect(decoded[3].kind == .property)
        #expect(decoded[4].kind == .object)
    }

    // MARK: - symbolKindFromMetadata

    @Test func testSymbolKindFromMetadataAllKinds() {
        let decoder = MetadataDecoder()
        let mapping: [(String, SymbolKind)] = [
            ("package", .package),
            ("class", .class),
            ("interface", .interface),
            ("object", .object),
            ("enumClass", .enumClass),
            ("annotationClass", .annotationClass),
            ("typeAlias", .typeAlias),
            ("function", .function),
            ("constructor", .constructor),
            ("property", .property),
            ("field", .field),
            ("typeParameter", .typeParameter),
            ("valueParameter", .valueParameter),
            ("local", .local),
            ("label", .label),
        ]
        for (token, expectedKind) in mapping {
            let result = decoder.symbolKindFromMetadata(token)
            #expect(result == expectedKind, "Expected \(expectedKind) for token '\(token)'")
        }
    }

    @Test func testSymbolKindFromMetadataReturnsNilForUnknown() {
        let decoder = MetadataDecoder()
        #expect(decoder.symbolKindFromMetadata("unknownType") == nil)
        #expect(decoder.symbolKindFromMetadata("") == nil)
        #expect(decoder.symbolKindFromMetadata("CLASS") == nil)
    }

    // MARK: - MetadataEncoder annotation encoding edge cases

    @Test func testSerializeAnnotationWithEmptyArguments() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.JvmStatic"),
            ]
        )
        let output = encoder.serialize([record])
        #expect(output.contains("annotations=kotlin.JvmStatic"))
    }

    @Test func testSerializeAnnotationWithUseSiteTargetAndArgs() {
        let encoder = MetadataEncoder()
        let decoder = MetadataDecoder()
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_KK",
            fqName: "test.fn",
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["msg1", "msg2"],
                    useSiteTarget: "set"
                ),
            ]
        )
        let serialized = encoder.serialize([record])
        let decoded = decoder.decode(serialized)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Deprecated")
        #expect(decoded[0].annotations[0].arguments == ["msg1", "msg2"])
        #expect(decoded[0].annotations[0].useSiteTarget == "set")
    }

    // MARK: - Nominal kinds coverage

    @Test func testSerializeInterfaceRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .interface,
            mangledName: "_KK_test__IFoo__I__",
            fqName: "test.IFoo",
            declaredVtableSize: 1
        )
        let output = encoder.serialize([record])
        #expect(output.contains("interface"))
        #expect(output.contains("vtable=1"))
    }

    @Test func testSerializeObjectRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .object,
            mangledName: "_KK_test__Companion__O__",
            fqName: "test.Companion",
            declaredInstanceSizeWords: 1
        )
        let output = encoder.serialize([record])
        #expect(output.contains("object"))
        #expect(output.contains("layoutWords=1"))
    }

    @Test func testSerializeEnumClassRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_KK_test__Color__E__",
            fqName: "test.Color",
            declaredFieldCount: 3
        )
        let output = encoder.serialize([record])
        #expect(output.contains("enumClass"))
        #expect(output.contains("fields=3"))
    }

    @Test func testSerializeAnnotationClassRecord() {
        let encoder = MetadataEncoder()
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_KK_test__MyAnno__A__",
            fqName: "test.MyAnno"
        )
        let output = encoder.serialize([record])
        #expect(output.contains("annotationClass"))
    }

    @Test func testDecodeFieldRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\nfield _KK fq=test.Foo.x schema=v1 sig=I\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].kind == .field)
    }

    @Test func testDecodeTypeAliasRecord() {
        let decoder = MetadataDecoder()
        let content = "symbols=1\ntypeAlias _KK fq=test.MyInt schema=v1 sig=I\n"
        let records = decoder.decode(content)
        #expect(records.count == 1)
        #expect(records[0].kind == .typeAlias)
        #expect(records[0].typeSignature == "I")
    }
}
#endif
