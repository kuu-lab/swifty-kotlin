#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LibMetadataSerializationTests {
    @Test func testMetadataRoundTripForInterface() {
        let record = MetadataRecord(
            kind: .interface,
            mangledName: "_kk_demo_IFoo",
            fqName: "demo.IFoo",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0,
            declaredVtableSize: 2,
            declaredItableSize: 0
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .interface)
        #expect(decoded[0].fqName == "demo.IFoo")
        #expect(decoded[0].declaredVtableSize == 2)
    }

    @Test func testMetadataRoundTripForObject() {
        let record = MetadataRecord(
            kind: .object,
            mangledName: "_kk_demo_Singleton",
            fqName: "demo.Singleton",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 1
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .object)
        #expect(decoded[0].fqName == "demo.Singleton")
        #expect(decoded[0].declaredInstanceSizeWords == 1)
    }

    @Test func testMetadataRoundTripForEnumClass() {
        let record = MetadataRecord(
            kind: .enumClass,
            mangledName: "_kk_demo_Color",
            fqName: "demo.Color",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 1,
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .enumClass)
        #expect(decoded[0].fqName == "demo.Color")
        #expect(decoded[0].isSealedClass)
    }

    @Test func testMetadataRoundTripForAnnotationClass() {
        let record = MetadataRecord(
            kind: .annotationClass,
            mangledName: "_kk_demo_MyAnno",
            fqName: "demo.MyAnno",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .annotationClass)
        #expect(decoded[0].fqName == "demo.MyAnno")
    }

    @Test func testMetadataRoundTripForConstructor() {
        let metadata = """
        symbols=1
        constructor _kk_demo_init fq=demo.Foo.init schema=v1 arity=2 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .constructor)
        #expect(decoded[0].fqName == "demo.Foo.init")
        #expect(decoded[0].arity == 2)
    }

    @Test func testMetadataEncoderIncludesArityForConstructor() {
        let record = MetadataRecord(
            kind: .constructor,
            mangledName: "_kk_demo_Foo_init",
            fqName: "demo.Foo.init",
            arity: 2,
            isSuspend: false,
            isInline: false
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("arity=2"))
        #expect(serialized.contains("suspend=0"))
        #expect(serialized.contains("inline=0"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .constructor)
        #expect(decoded[0].fqName == "demo.Foo.init")
        #expect(decoded[0].arity == 2)
    }

    @Test func testMetadataRoundTripForSuspendFunction() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_demo_fetch",
            fqName: "demo.fetch",
            arity: 1,
            isSuspend: true,
            isInline: false,
            typeSignature: "F1<S,U>"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("suspend=1"))
        #expect(serialized.contains("inline=0"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].isSuspend)
        #expect(!decoded[0].isInline)
        #expect(decoded[0].typeSignature == "F1<S,U>")
    }

    @Test func testMetadataRoundTripForFunctionWithExternalLinkName() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_demo_add",
            fqName: "demo.add",
            arity: 2,
            externalLinkName: "_demo_add_impl"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("link=_demo_add_impl"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].externalLinkName == "_demo_add_impl")
    }

    // MARK: - Annotation Encoding/Decoding Edge Cases

    @Test func testAnnotationRoundTripWithMultipleArguments() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["old name", "use new() instead", "WARNING"],
                useSiteTarget: nil
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_old",
            fqName: "demo.old",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].arguments.count == 3)
        #expect(decoded[0].annotations[0].arguments[0] == "old name")
        #expect(decoded[0].annotations[0].arguments[1] == "use new() instead")
        #expect(decoded[0].annotations[0].arguments[2] == "WARNING")
    }

    @Test func testAnnotationRoundTripWithSpecialCharactersInArguments() {
        // Base64 encoding should handle special characters safely
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "custom.Config",
                arguments: ["key=value", "a|b|c", "semi;colon", "space here", "emoji\u{1F600}"],
                useSiteTarget: nil
            ),
        ]
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_kk_cfg",
            fqName: "demo.cfg",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].arguments.count == 5)
        #expect(decoded[0].annotations[0].arguments[0] == "key=value")
        #expect(decoded[0].annotations[0].arguments[1] == "a|b|c")
        #expect(decoded[0].annotations[0].arguments[2] == "semi;colon")
        #expect(decoded[0].annotations[0].arguments[3] == "space here")
        #expect(decoded[0].annotations[0].arguments[4] == "emoji\u{1F600}")
    }

    @Test func testAnnotationRoundTripWithMultipleAnnotationsOnOneSymbol() {
        let annotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.jvm.JvmStatic", useSiteTarget: "get"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.Suppress", arguments: ["UNCHECKED_CAST"]),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_foo",
            fqName: "demo.foo",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 3)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Deprecated")
        #expect(decoded[0].annotations[0].arguments.isEmpty)
        #expect(decoded[0].annotations[0].useSiteTarget == nil)
        #expect(decoded[0].annotations[1].annotationFQName == "kotlin.jvm.JvmStatic")
        #expect(decoded[0].annotations[1].useSiteTarget == "get")
        #expect(decoded[0].annotations[2].annotationFQName == "kotlin.Suppress")
        #expect(decoded[0].annotations[2].arguments == ["UNCHECKED_CAST"])
    }

    @Test func testAnnotationRoundTripWithWasExperimentalArgument() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.WasExperimental",
                arguments: ["markerClass = demo.ExperimentalApi::class"]
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_stable",
            fqName: "demo.stable",
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
    }

    @Test func testAnnotationRecordEquatable() {
        let a = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["msg"], useSiteTarget: "get")
        let b = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["msg"], useSiteTarget: "get")
        let c = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["other"], useSiteTarget: "get")
        let d = MetadataAnnotationRecord(annotationFQName: "kotlin.Suppress", arguments: ["msg"], useSiteTarget: "get")
        let e = MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["msg"], useSiteTarget: nil)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
        #expect(a != e)
    }

    // MARK: - MetadataRecord Default Values

    @Test func testMetadataRecordDefaultInitializerValues() {
        let record = MetadataRecord(kind: .function)
        #expect(record.kind == .function)
        #expect(record.mangledName == "")
        #expect(record.fqName == "")
        #expect(record.arity == 0)
        #expect(!record.isSuspend)
        #expect(!record.isInline)
        #expect(record.typeSignature == nil)
        #expect(record.externalLinkName == nil)
        #expect(record.declaredFieldCount == nil)
        #expect(record.declaredInstanceSizeWords == nil)
        #expect(record.declaredVtableSize == nil)
        #expect(record.declaredItableSize == nil)
        #expect(record.superFQName == nil)
        #expect(record.fieldOffsets == nil)
        #expect(record.vtableSlots == nil)
        #expect(record.itableSlots == nil)
        #expect(!record.isDataClass)
        #expect(!record.isSealedClass)
        #expect(record.annotations.isEmpty)
    }

    // MARK: - Serialize Output Format Verification

    @Test func testMetadataSerializeSymbolsHeaderLine() {
        let records = [
            MetadataRecord(kind: .function, mangledName: "_kk_a", fqName: "a"),
            MetadataRecord(kind: .function, mangledName: "_kk_b", fqName: "b"),
            MetadataRecord(kind: .function, mangledName: "_kk_c", fqName: "c"),
        ]
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize(records)
        let lines = serialized.split(whereSeparator: \.isNewline)
        #expect(lines.first.map(String.init) == "symbols=3")
        #expect(lines.count == 4) // header + 3 records
    }

    @Test func testMetadataSerializeLayoutFieldsOnlyForNominalKinds() {
        // Layout fields should appear for class but NOT for function
        let classRecord = MetadataRecord(
            kind: .class,
            mangledName: "_kk_C",
            fqName: "demo.C",
            declaredFieldCount: 1,
            declaredInstanceSizeWords: 2
        )
        let funcRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_f",
            fqName: "demo.f",
            declaredFieldCount: 1, // should be ignored for function
            declaredInstanceSizeWords: 2 // should be ignored for function
        )
        let encoder = MetadataEncoder()

        let classStr = encoder.serialize([classRecord])
        #expect(classStr.contains("fields=1"))
        #expect(classStr.contains("layoutWords=2"))

        let funcStr = encoder.serialize([funcRecord])
        #expect(!funcStr.contains("fields="))
        #expect(!funcStr.contains("layoutWords="))
    }

    @Test func testMetadataSerializeArityOnlyForFunctions() {
        // Arity should appear for function but NOT for class
        let funcRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_f",
            fqName: "demo.f",
            arity: 3
        )
        let classRecord = MetadataRecord(
            kind: .class,
            mangledName: "_kk_C",
            fqName: "demo.C"
        )
        let encoder = MetadataEncoder()

        let funcStr = encoder.serialize([funcRecord])
        #expect(funcStr.contains("arity=3"))

        let classStr = encoder.serialize([classRecord])
        #expect(!classStr.contains("arity="))
    }

        // MARK: - Integration: library metadata imports consolidated into a single runToKIR

    @Test func testLibraryMetadataImports() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // Sample 0: sealed class import
        let sealedDir = baseDir.appendingPathComponent("sealed.kklib")
        try fm.createDirectory(at: sealedDir, withIntermediateDirectories: true)
        try """
        {
          "formatVersion": 1,
          "moduleName": "ExtSealedClass",
          "metadata": "metadata.bin"
        }
        """.write(to: sealedDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try """
        symbols=1
        class _kk_Shape fq=ext.Shape schema=v1 fields=0 layoutWords=2 vtable=0 itable=0 sealedClass=1
        """.write(to: sealedDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        // Sample 1: annotated function import
        let annotatedDir = baseDir.appendingPathComponent("annotated.kklib")
        try fm.createDirectory(at: annotatedDir, withIntermediateDirectories: true)
        let encoder = MetadataEncoder()
        let annotatedRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_ext_old",
            fqName: "ext.oldMethod",
            arity: 0,
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.Deprecated", arguments: ["replaced"]),
            ]
        )
        let annotatedSerialized = encoder.serialize([annotatedRecord])
        let annotatedFunctionLine = annotatedSerialized.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("function") }
        try """
        {
          "formatVersion": 1,
          "moduleName": "ExtAnnotated",
          "metadata": "metadata.bin"
        }
        """.write(to: annotatedDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "symbols=1\n\(annotatedFunctionLine!)\n".write(to: annotatedDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        // Sample 2: WasExperimental annotated function import
        let stableDir = baseDir.appendingPathComponent("stable.kklib")
        try fm.createDirectory(at: stableDir, withIntermediateDirectories: true)
        let stableRecord = MetadataRecord(
            kind: .function,
            mangledName: "_kk_ext_stable",
            fqName: "ext.stableApi",
            arity: 0,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.WasExperimental",
                    arguments: ["markerClass = ext.ExperimentalApi::class"]
                ),
            ]
        )
        let stableSerialized = encoder.serialize([stableRecord])
        let stableFunctionLine = stableSerialized.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("function") }
        try """
        {
          "formatVersion": 1,
          "moduleName": "ExtStable",
          "metadata": "metadata.bin"
        }
        """.write(to: stableDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "symbols=1\n\(stableFunctionLine!)\n".write(to: stableDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let sources: [String] = [
            """
            package sample0
            fun main() = 0
            """,
            """
            package sample1
            fun main() = 0
            """,
            """
            package sample2
            fun main() = 0
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                searchPaths: [sealedDir.path, annotatedDir.path, stableDir.path]
            )
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            do {
                let shapeSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "Shape" && symbol.kind == .class
                }
                #expect(shapeSymbol != nil)
                #expect(shapeSymbol?.flags.contains(.sealedType) ?? false)
                #expect(!(shapeSymbol?.flags.contains(.dataType) ?? true))
            }

            do {
                let ext = interner.intern("ext")
                let oldMethod = interner.intern("oldMethod")
                let symbolID = try #require(sema.symbols.lookupAll(fqName: [ext, oldMethod]).first)
                let annotations = sema.symbols.annotations(for: symbolID)
                #expect(annotations.count == 1)
                #expect(annotations[0].annotationFQName == "kotlin.Deprecated")
                #expect(annotations[0].arguments == ["replaced"])
            }

            do {
                let ext = interner.intern("ext")
                let stableApi = interner.intern("stableApi")
                let symbolID = try #require(sema.symbols.lookupAll(fqName: [ext, stableApi]).first)
                let annotations = sema.symbols.annotations(for: symbolID)
                #expect(annotations.count == 1)
                #expect(annotations[0].annotationFQName == "kotlin.WasExperimental")
                #expect(annotations[0].arguments == ["markerClass = ext.ExperimentalApi::class"])
            }
        }
    }
}
#endif
