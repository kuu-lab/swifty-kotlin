import Foundation
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationAnnotationMetadataTests {
    @Test(arguments: [false, true])
    func sourceAnnotationContractAndBinaryMetadataSurvive(fromSource: Bool) throws {
        let context = try frontend("""
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
        import kotlinx.serialization.*
        @SerialInfo @Target(AnnotationTarget.CLASS) annotation class Tag(val value: String)
        @InheritableSerialInfo annotation class Inherited
        @SerialName("wire.Tagged") @Tag("tag") class Tagged
        """, fromSource: fromSource)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" })
        let sema = try #require(context.sema)
        for name in ["SerialName", "SerialInfo", "InheritableSerialInfo"] {
            let symbol = try #require(sema.symbols.lookup(fqName: ["kotlinx", "serialization", name].map(context.interner.intern)))
            #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
            #expect(sema.symbols.symbol(symbol)?.visibility == .public)
            let records = sema.symbols.annotations(for: symbol)
            #expect(records.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" })
            let target = try #require(records.first { $0.annotationFQName == "kotlin.annotation.Target" })
            if name == "SerialName" {
                #expect(target.arguments.contains { $0.contains("PROPERTY") })
                #expect(target.arguments.contains { $0.contains("CLASS") })
                #expect(!records.contains { $0.annotationFQName == "kotlinx.serialization.ExperimentalSerializationApi" })
            } else {
                #expect(target.arguments.count == 1 && target.arguments[0].contains("ANNOTATION_CLASS"))
                #expect(records.contains { $0.annotationFQName == "kotlinx.serialization.ExperimentalSerializationApi" })
            }
            #expect(resolvedAnnotationRetention(MetadataAnnotationRecord(annotationFQName: "kotlinx.serialization." + name),
                symbols: sema.symbols, interner: context.interner) == (name == "SerialName" ? .runtime : .binary))
        }
        let records = MetadataEncoder().buildRecords(symbols: sema.symbols, types: sema.types,
            moduleName: "SerialAnnotationMetadata", interner: context.interner, functionLinkNames: [:])
        let decoded = MetadataDecoder().decode(MetadataEncoder().serialize(records))
        let tag = try #require(decoded.first { $0.fqName == "Tag" })
        let marker = try #require(tag.annotations.first { $0.annotationFQName == "kotlinx.serialization.SerialInfo" })
        #expect(marker.retention == .binary && marker.factoryLinkName == nil)
    }

    @Test(arguments: [false, true])
    func stableAnnotationAndValidPropertyTargetsNeedNoOptIn(fromSource: Bool) throws {
        let context = try frontend("""
        import kotlinx.serialization.SerialName
        @SerialName("Record") class Record(@SerialName("value") val value: Int)
        @SerialName("top") val top: Int = 1
        class Explicit(@property:SerialName("property") val value: Int)
        fun runtime(value: String): SerialName = SerialName(value = value)
        fun empty(): SerialName = SerialName("")
        """, fromSource: fromSource)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" })
    }

    @Test(arguments: [false, true])
    func experimentalMetaAnnotationsWarnButDoNotMarkCustomAnnotations(fromSource: Bool) throws {
        for usage in [
            "@SerialInfo annotation class Tag",
            "@InheritableSerialInfo annotation class Inherited",
            "fun meta(value: SerialInfo) {}",
            "fun inherited(value: InheritableSerialInfo) {}",
            "fun meta(): Annotation = SerialInfo()",
            "fun inherited(): Annotation = InheritableSerialInfo()",
        ] {
            let warnings = try frontend("import kotlinx.serialization.*\n" + usage, fromSource: fromSource).diagnostics.diagnostics
            #expect(!warnings.contains { $0.severity == .error }, "\(usage): \(warnings)")
            #expect(warnings.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning && $0.message.contains("ExperimentalSerializationApi") }, "\(usage): \(warnings)")
        }
        let context = try frontend("""
        import kotlinx.serialization.*
        @OptIn(ExperimentalSerializationApi::class)
        @SerialInfo annotation class Tag(val value: String)
        @OptIn(ExperimentalSerializationApi::class)
        @InheritableSerialInfo annotation class Inherited(val value: String)
        @Tag("class") class Tagged
        fun ordinary(value: Tag): Tag = Tag(value.value)
        fun inherited(value: Inherited): Inherited = Inherited(value.value)
        """, fromSource: fromSource)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func invalidTargetsAndConstructorArgumentsAreRejected(fromSource: Bool) throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/reference_cases/serialization_annotation_api_invalid.kt"), encoding: .utf8)
        let context = try frontend(source, fromSource: fromSource)
        let diagnostics = context.diagnostics.diagnostics
        for usage in [
            "@SerialName(\"fun\") fun badNameFunction() {}",
            "fun badParameter(@SerialName(\"param\") value: Int) {}",
            "class BadParam(@param:SerialName(\"param\") val value: Int)",
            "class BadField(@field:SerialName(\"field\") val value: Int)",
            "class BadGetter(@get:SerialName(\"getter\") val value: Int)",
            "@SerialInfo class NotAnnotation",
            "@InheritableSerialInfo class NotInheritedAnnotation",
            "@SerialInfo fun badMetaFunction() {}",
            "@InheritableSerialInfo val badMetaProperty: Int = 1",
        ] {
            let prefix = "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.*\n"
            let targetDiagnostics = try frontend(prefix + usage, fromSource: fromSource).diagnostics.diagnostics
            #expect(targetDiagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(usage): \(targetDiagnostics)")
        }
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST" })
        for call in ["SerialName()", "SerialName(null)", "SerialName(1)", "SerialName(name = \"wrong\")"] {
            let range = try #require(source.range(of: call))
            let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
            #expect(diagnostics.contains { $0.severity == .error && $0.primaryRange?.start.offset == offset }, "\(call): \(diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func experimentalAnnotationsDoNotPropagateTheirErrorMarker(fromSource: Bool) throws {
        let declarations = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR) annotation class Marker
        @Marker annotation class Meta
        @OptIn(Marker::class) @Meta annotation class Tag(val value: String)
        @OptIn(Marker::class) @Meta fun stable(): Int = 1
        @Marker fun experimental(): Int = 2
        """
        let safe = try frontend(declarations + """
        \nfun ordinary(value: Tag): Tag { stable(); return Tag(value.value) }
        """, fromSource: fromSource)
        #expect(!safe.diagnostics.hasError, "\(safe.diagnostics.diagnostics)")
        #expect(!safe.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" })
        for usage in [
            "@Meta class InvalidSite",
            "fun needsType(value: Meta) {}",
            "fun needsConstructor(): Annotation = Meta()",
            "fun needsFunction(): Int = experimental()",
        ] {
            let invalid = try frontend(declarations + "\n" + usage, fromSource: fromSource).diagnostics.diagnostics
            #expect(invalid.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error && $0.message.contains("Marker") }, "\(usage): \(invalid)")
        }
    }

    private func frontend(_ source: String, fromSource: Bool) throws -> CompilationContext {
        let input = "/tmp/serialization-annotation-contract-\(UUID().uuidString).kt"
        let stdlib: String?
        if fromSource {
            stdlib = nil
        } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "SerialAnnotationContract", inputs: [input], outputPath: "/tmp/serialization-annotation-contract", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
    }
}
