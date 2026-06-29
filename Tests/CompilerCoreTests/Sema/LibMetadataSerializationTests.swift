#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibMetadataSerializationTests {
    // MARK: - MetadataSerializer Round-Trip Tests

    @Test func testMetadataEncoderDecoderRoundTripForFunctionRecord() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_ext_id",
            fqName: "ext.id",
            arity: 1,
            isSuspend: false,
            isInline: true,
            typeSignature: "F1<I,I>",
            externalLinkName: "_ext_id"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        let r = decoded[0]
        #expect(r.kind == .function)
        #expect(r.mangledName == "_kk_ext_id")
        #expect(r.fqName == "ext.id")
        #expect(r.arity == 1)
        #expect(r.isSuspend == false)
        #expect(r.isInline == true)
        #expect(r.typeSignature == "F1<I,I>")
        #expect(r.externalLinkName == "_ext_id")
    }

    @Test func testMetadataEncoderDecoderRoundTripForClassWithLayout() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_ext_Box",
            fqName: "ext.Box",
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 1,
            declaredItableSize: 1,
            superFQName: "ext.Base",
            fieldOffsets: "ext.Box.x@2,ext.Box.y@3",
            vtableSlots: "ext.Box.get#0#0@0",
            itableSlots: "ext.IFace@0"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        let r = decoded[0]
        #expect(r.kind == .class)
        #expect(r.fqName == "ext.Box")
        #expect(r.declaredFieldCount == 2)
        #expect(r.declaredInstanceSizeWords == 4)
        #expect(r.declaredVtableSize == 1)
        #expect(r.declaredItableSize == 1)
        #expect(r.superFQName == "ext.Base")
        #expect(r.fieldOffsets == "ext.Box.x@2,ext.Box.y@3")
        #expect(r.vtableSlots == "ext.Box.get#0#0@0")
        #expect(r.itableSlots == "ext.IFace@0")
    }

    @Test func testMetadataEncoderDecoderRoundTripForDataClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_data_Point",
            fqName: "demo.Point",
            isDataClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("dataClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].isDataClass)
        #expect(!decoded[0].isSealedClass)
    }

    @Test func testMetadataEncoderDecoderRoundTripForSealedClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_sealed_Shape",
            fqName: "demo.Shape",
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sealedClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(!decoded[0].isDataClass)
        #expect(decoded[0].isSealedClass)
    }

    @Test func testMetadataEncoderDecoderRoundTripForAnnotations() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["Use newMethod instead"],
                useSiteTarget: nil
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.jvm.JvmStatic",
                arguments: [],
                useSiteTarget: "get"
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_old",
            fqName: "demo.oldMethod",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("annotations="))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 2)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Deprecated")
        #expect(decoded[0].annotations[0].arguments == ["Use newMethod instead"])
        #expect(decoded[0].annotations[0].useSiteTarget == nil)
        #expect(decoded[0].annotations[1].annotationFQName == "kotlin.jvm.JvmStatic")
        #expect(decoded[0].annotations[1].arguments == [])
        #expect(decoded[0].annotations[1].useSiteTarget == "get")
    }

    @Test func testMetadataEncoderDecoderRoundTripForWasExperimentalAnnotation() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.WasExperimental",
                arguments: ["markerClass = demo.ExperimentalApi::class"],
                useSiteTarget: nil
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_stable_api",
            fqName: "demo.stableApi",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.WasExperimental")
        #expect(decoded[0].annotations[0].arguments == ["markerClass = demo.ExperimentalApi::class"])
        #expect(decoded[0].annotations[0].useSiteTarget == nil)
    }

    @Test func testMetadataEncoderDecoderRoundTripForDataAndSealedBothSet() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_ext_Weird",
            fqName: "ext.Weird",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0,
            isDataClass: true,
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("dataClass=1"))
        #expect(serialized.contains("sealedClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "ext.Weird")
        #expect(decoded[0].isDataClass)
        #expect(decoded[0].isSealedClass)
    }

    @Test func testMetadataDecoderAcceptsLegacyRecordsWithoutSchema() {
        let legacy = """
        symbols=1
        class _kk_ext_C fq=ext.C fields=0 layoutWords=3 vtable=0 itable=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(legacy)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "ext.C")
    }

    @Test func testMetadataDecoderRejectsRecordsWithUnsupportedSchema() {
        let future = """
        symbols=1
        class _kk_ext_C fq=ext.C schema=v2 fields=0 layoutWords=3 vtable=0 itable=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(future)
        #expect(decoded.count == 0)
    }

    @Test func testMetadataRoundTripMultipleRecords() {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_kk_Point",
                fqName: "demo.Point",
                declaredFieldCount: 2,
                declaredInstanceSizeWords: 4,
                isDataClass: true,
                annotations: [
                    MetadataAnnotationRecord(annotationFQName: "kotlin.Serializable"),
                ]
            ),
            MetadataRecord(
                kind: .function,
                mangledName: "_kk_demo_greet",
                fqName: "demo.greet",
                arity: 1,
                isSuspend: true,
                typeSignature: "F1<S,U>"
            ),
            MetadataRecord(
                kind: .property,
                mangledName: "_kk_demo_name",
                fqName: "demo.name",
                typeSignature: "S"
            ),
        ]
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize(records)
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 3)

        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "demo.Point")
        #expect(decoded[0].isDataClass)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Serializable")

        #expect(decoded[1].kind == .function)
        #expect(decoded[1].fqName == "demo.greet")
        #expect(decoded[1].arity == 1)
        #expect(decoded[1].isSuspend)
        #expect(decoded[1].typeSignature == "F1<S,U>")

        #expect(decoded[2].kind == .property)
        #expect(decoded[2].fqName == "demo.name")
        #expect(decoded[2].typeSignature == "S")
    }

    @Test func testMetadataImportRestoresDataClassFlagViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtDataClass",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _kk_Point fq=ext.Point schema=v1 fields=2 layoutWords=4 vtable=0 itable=0 dataClass=1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DataClassImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let pointSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Point" && symbol.kind == .class
            }
            #expect(pointSymbol != nil)
            #expect(pointSymbol?.flags.contains(.dataType) ?? false)
            #expect(!(pointSymbol?.flags.contains(.sealedType) ?? true))
        }
    }

    // MARK: - MetadataDecoder.symbolKindFromMetadata Unit Tests

    @Test func testSymbolKindFromMetadataReturnsCorrectKindForAllTokens() {
        let decoder = MetadataDecoder()
        #expect(decoder.symbolKindFromMetadata("package") == .package)
        #expect(decoder.symbolKindFromMetadata("class") == .class)
        #expect(decoder.symbolKindFromMetadata("interface") == .interface)
        #expect(decoder.symbolKindFromMetadata("object") == .object)
        #expect(decoder.symbolKindFromMetadata("enumClass") == .enumClass)
        #expect(decoder.symbolKindFromMetadata("annotationClass") == .annotationClass)
        #expect(decoder.symbolKindFromMetadata("typeAlias") == .typeAlias)
        #expect(decoder.symbolKindFromMetadata("function") == .function)
        #expect(decoder.symbolKindFromMetadata("constructor") == .constructor)
        #expect(decoder.symbolKindFromMetadata("property") == .property)
        #expect(decoder.symbolKindFromMetadata("field") == .field)
        #expect(decoder.symbolKindFromMetadata("typeParameter") == .typeParameter)
        #expect(decoder.symbolKindFromMetadata("valueParameter") == .valueParameter)
        #expect(decoder.symbolKindFromMetadata("local") == .local)
        #expect(decoder.symbolKindFromMetadata("label") == .label)
    }

    @Test func testSymbolKindFromMetadataReturnsNilForUnknownToken() {
        let decoder = MetadataDecoder()
        #expect(decoder.symbolKindFromMetadata("") == nil)
        #expect(decoder.symbolKindFromMetadata("unknown") == nil)
        #expect(decoder.symbolKindFromMetadata("CLASS") == nil)
        #expect(decoder.symbolKindFromMetadata("Function") == nil)
        #expect(decoder.symbolKindFromMetadata("backingField") == .backingField)
    }

    // MARK: - MetadataDecoder Edge Cases

    @Test func testMetadataDecoderReturnsEmptyForEmptyInput() {
        let decoder = MetadataDecoder()
        #expect(decoder.decode("").count == 0)
    }

    @Test func testMetadataDecoderReturnsEmptyForOnlyHeader() {
        let decoder = MetadataDecoder()
        #expect(decoder.decode("symbols=5\n").count == 0)
    }

    @Test func testMetadataDecoderReturnsEmptyForWhitespaceOnly() {
        let decoder = MetadataDecoder()
        #expect(decoder.decode("   \n  \n").count == 0)
    }

    @Test func testMetadataDecoderSkipsLinesWithUnknownKind() {
        let metadata = """
        symbols=2
        unknownKind _kk_foo fq=demo.Foo schema=v1
        function _kk_bar fq=demo.bar schema=v1 arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].fqName == "demo.bar")
    }

    @Test func testMetadataDecoderSkipsLinesWithoutFqField() {
        let metadata = """
        symbols=1
        function _kk_bar arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 0)
    }

    @Test func testMetadataDecoderSkipsLinesWithEmptyFqField() {
        let metadata = """
        symbols=1
        function _kk_bar fq= arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 0)
    }

    @Test func testMetadataDecoderIgnoresTokensWithoutEqualsSign() {
        // Tokens without '=' should be silently skipped (except kind and mangledName)
        let metadata = """
        symbols=1
        function _kk_bar fq=demo.bar schema=v1 randomtoken arity=2 suspend=1 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].arity == 2)
        #expect(decoded[0].isSuspend)
    }

    @Test func testMetadataDecoderIgnoresUnknownKeyValuePairs() {
        let metadata = """
        symbols=1
        class _kk_Foo fq=demo.Foo schema=v1 futureKey=futureValue fields=1 layoutWords=2
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].fqName == "demo.Foo")
        #expect(decoded[0].declaredFieldCount == 1)
    }

    // MARK: - MetadataEncoder Edge Cases

    @Test func testMetadataEncoderSerializeEmptyRecordsArray() {
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([])
        #expect(serialized == "symbols=0\n")
    }

    @Test func testMetadataEncoderDoesNotEmitDataClassWhenFalse() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_Foo",
            fqName: "demo.Foo"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(!serialized.contains("dataClass="))
        #expect(!serialized.contains("sealedClass="))
        #expect(!serialized.contains("annotations="))
    }

    @Test func testMetadataEncoderDoesNotEmitAnnotationsWhenEmpty() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_foo",
            fqName: "demo.foo",
            annotations: []
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(!serialized.contains("annotations="))
    }

    // MARK: - Round-Trip for Each Symbol Kind

    @Test func testMetadataRoundTripForPropertyWithTypeSignature() {
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_kk_demo_name",
            fqName: "demo.name",
            typeSignature: "S"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sig=S"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .property)
        #expect(decoded[0].fqName == "demo.name")
        #expect(decoded[0].typeSignature == "S")
    }

    @Test func testMetadataRoundTripForFieldWithTypeSignature() {
        let record = MetadataRecord(
            kind: .field,
            mangledName: "_kk_demo_x",
            fqName: "demo.x",
            typeSignature: "I"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sig=I"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .field)
        #expect(decoded[0].typeSignature == "I")
    }

    @Test func testMetadataRoundTripForTypeAliasWithTypeSignature() {
        let record = MetadataRecord(
            kind: .typeAlias,
            mangledName: "_kk_demo_ID",
            fqName: "demo.ID",
            typeSignature: "L"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sig=L"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .typeAlias)
        #expect(decoded[0].fqName == "demo.ID")
        #expect(decoded[0].typeSignature == "L")
    }
}
#endif
