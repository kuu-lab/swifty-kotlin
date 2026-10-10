import Foundation
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationPropertyAnnotationMetadataTests {
    @Test(arguments: [false, true])
    func stablePropertyAnnotationMetadataSurvives(fromSource: Bool) throws {
        let context = try frontend("""
        import kotlinx.serialization.*
        class Fields(@Required val required: Int = 1, @Transient val temporary: Int = 2,
                     @EncodeDefault(EncodeDefault.Mode.NEVER) val optional: Int = 3)
        @property:Required val top: Int = 1
        fun mode(): EncodeDefault.Mode = EncodeDefault().mode
        """, fromSource: fromSource)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" })
        let sema = try #require(context.sema)
        for name in ["Required", "Transient", "EncodeDefault"] {
            let fqName = "kotlinx.serialization." + name
            let symbol = try #require(sema.symbols.lookup(fqName: fqName.split(separator: ".").map { context.interner.intern(String($0)) }))
            #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
            #expect(sema.symbols.symbol(symbol)?.visibility == .public)
            let annotations = sema.symbols.annotations(for: symbol)
            #expect(annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" })
            #expect(!annotations.contains { $0.annotationFQName == "kotlinx.serialization.ExperimentalSerializationApi" })
            let target = try #require(annotations.first { $0.annotationFQName == "kotlin.annotation.Target" })
            #expect(target.arguments.count == 1 && target.arguments[0].contains("PROPERTY"))
            #expect(resolvedAnnotationRetention(MetadataAnnotationRecord(annotationFQName: fqName),
                symbols: sema.symbols, interner: context.interner) == .runtime)
        }
        let mode = try #require(sema.symbols.lookup(fqName: ["kotlinx", "serialization", "EncodeDefault", "Mode"].map(context.interner.intern)))
        #expect(sema.symbols.symbol(mode)?.kind == .enumClass)
        #expect(sema.symbols.symbol(mode)?.visibility == .public)
        let records = MetadataEncoder().buildRecords(symbols: sema.symbols, types: sema.types,
            moduleName: "PropertyAnnotationMetadata", interner: context.interner, functionLinkNames: [:])
        let decoded = MetadataDecoder().decode(MetadataEncoder().serialize(records))
        for (field, name) in [("required", "Required"), ("temporary", "Transient"), ("optional", "EncodeDefault")] {
            let record = try #require(decoded.first { $0.fqName == "Fields." + field })
            let annotation = try #require(record.annotations.first { $0.annotationFQName == "kotlinx.serialization." + name })
            #expect(resolvedAnnotationRetention(annotation, symbols: sema.symbols, interner: context.interner) == .runtime)
            let symbol = try #require(sema.symbols.lookup(
                fqName: [context.interner.intern("Fields"), context.interner.intern(field)]
            ))
            #expect(sema.symbols.annotations(for: symbol).contains { $0.factorySymbol != nil })
        }
    }

    @Test(arguments: [false, true])
    func primaryPropertiesReceiveOnlyTheirApplicableAnnotations(fromSource: Bool) throws {
        let context = try frontend("""
        @Target(AnnotationTarget.PROPERTY) annotation class PropertyTag(val value: String)
        @Target(AnnotationTarget.VALUE_PARAMETER, AnnotationTarget.PROPERTY) annotation class DualTag(val value: String)
        @Target(AnnotationTarget.FIELD) annotation class FieldTag
        @Target(AnnotationTarget.PROPERTY_GETTER) annotation class GetterTag
        typealias Alias = PropertyTag
        class Aliased(@Alias("alias") val aliasValue: Int)
        class Targeted(@PropertyTag("implicit") val implicit: Int,
            @property:PropertyTag("explicit") val explicit: Int,
            @DualTag("default-param") val parameter: Int,
            @param:DualTag("explicit-param") val explicitParameter: Int,
            @field:FieldTag val field: Int, @get:GetterTag val getter: Int) {
            class Nested(@PropertyTag("nested") val nested: Int)
        }
        fun local() { class Local(@PropertyTag("local") val localValue: Int); Local(1) }
        @Target(AnnotationTarget.PROPERTY) annotation class Tag(val value: String)
        class Outer {
            @Target(AnnotationTarget.PROPERTY) annotation class Tag(val value: String)
            fun local() { class Local(@Tag("nested-tag") val lexicalValue: Int); Local(1) }
            fun nestedLocal() {
                class First {
                    fun nested() { class Second(@Tag("nested-local-tag") val nestedLexicalValue: Int); Second(1) }
                }
                First().nested()
            }
        }
        """, fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        for name in ["implicit", "explicit", "nested", "localValue", "aliasValue"] {
            let symbol = try #require(sema.symbols.allSymbols().first { $0.kind == .property && context.interner.resolve($0.name) == name })
            let annotation = try #require(sema.symbols.annotations(for: symbol.id).first { $0.annotationFQName == "PropertyTag" })
            #expect(annotation.factorySymbol != nil)
        }
        for name in ["parameter", "explicitParameter", "field", "getter"] {
            let symbol = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Targeted"), context.interner.intern(name)]))
            #expect(sema.symbols.annotations(for: symbol).isEmpty)
        }
        for name in ["lexicalValue", "nestedLexicalValue"] {
            let lexicalProperty = try #require(sema.symbols.allSymbols().first {
                $0.kind == .property && context.interner.resolve($0.name) == name
            })
            let lexicalAnnotation = try #require(sema.symbols.annotations(for: lexicalProperty.id).first)
            #expect(lexicalAnnotation.annotationFQName == "Outer.Tag")
            #expect(lexicalAnnotation.factorySymbol != nil)
        }
    }

    @Test(arguments: [false, true])
    func propertySuppressionDoesNotReachOtherMembers(fromSource: Bool) throws {
        let source = """
        class Suppressed(@property:Suppress("KSWIFTK-SEMA-0022") val value: Int = suppressedMissing) {
            fun broken(): Int = memberMissing
        }
        """
        let context = try frontend(source, fromSource: fromSource)
        let member = try #require(source.range(of: "memberMissing"))
        let memberOffset = source.utf8.distance(from: source.utf8.startIndex, to: member.lowerBound)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0022" && $0.primaryRange?.start.offset == memberOffset
        })
        let initializer = try #require(source.range(of: "suppressedMissing"))
        let initializerOffset = source.utf8.distance(from: source.utf8.startIndex, to: initializer.lowerBound)
        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0022" && $0.primaryRange?.start.offset == initializerOffset
        })
    }

    @Test(arguments: [false, true])
    func propertyAnnotationTargetsRejectOtherSites(fromSource: Bool) throws {
        let probes = [
            "@Required class BadRequired", "@Transient class BadTransient", "@EncodeDefault class BadDefault",
            "@Required fun badRequired() {}", "@Transient fun badTransient() {}", "@EncodeDefault fun badDefault() {}",
            "class BadField(@field:Required val value: Int)", "class BadGetter(@get:Transient val value: Int)",
            "class BadParameter(@param:EncodeDefault val value: Int)",
        ]
        let inputs = probes.indices.map { "/tmp/property-target-\(UUID().uuidString)-\($0).kt" }
        let sources = Dictionary(uniqueKeysWithValues: zip(inputs, probes).map { ($0.0, Data(("import kotlinx.serialization.*\n" + $0.1).utf8)) })
        let context = CompilerDriver().runFrontend(options: try options(inputs: inputs, fromSource: fromSource), inMemorySources: sources).context
        for (input, probe) in zip(inputs, probes) {
            let file = try #require(context.sourceManager.fileID(forPath: input))
            #expect(context.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" && $0.primaryRange?.start.file == file
            }, "\(probe): \(context.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func invalidArgumentsAndNonconstantModesAreRejected(fromSource: Bool) throws {
        let source = """
        import kotlinx.serialization.*
        fun badArguments() {
            Required(1)
            Transient(1)
            EncodeDefault(null)
            EncodeDefault(1)
            EncodeDefault(value = EncodeDefault.Mode.ALWAYS)
        }
        @EncodeDefault(EncodeDefault.Mode.valueOf("ALWAYS")) val nonconstant: Int = 1
        class InvalidPrimary(@EncodeDefault(EncodeDefault.Mode.valueOf("NEVER")) val nonconstant: Int)
        """
        let context = try frontend(source, fromSource: fromSource)
        let diagnostics = context.diagnostics.diagnostics
        for call in ["Required(1)", "Transient(1)", "EncodeDefault(null)", "EncodeDefault(1)", "EncodeDefault(value = EncodeDefault.Mode.ALWAYS)"] {
            let range = try #require(source.range(of: call))
            let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
            #expect(diagnostics.contains { $0.severity == .error && $0.primaryRange?.start.offset == offset }, "\(call): \(diagnostics)")
        }
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST" })
        let primary = try #require(source.range(of: "EncodeDefault.Mode.valueOf(\"NEVER\")"))
        let primaryOffset = source.utf8.distance(from: source.utf8.startIndex, to: primary.lowerBound)
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST" && $0.primaryRange?.start.offset == primaryOffset })
    }

    private func frontend(_ source: String, fromSource: Bool) throws -> CompilationContext {
        let input = "/tmp/serialization-property-contract-\(UUID().uuidString).kt"
        return CompilerDriver().runFrontend(options: try options(inputs: [input], fromSource: fromSource),
            inMemorySources: [input: Data(source.utf8)]).context
    }

    private func options(inputs: [String], fromSource: Bool) throws -> CompilerOptions {
        let stdlib: String?
        if fromSource {
            stdlib = nil
        } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerOptions(moduleName: "PropertyAnnotationContract", inputs: inputs, outputPath: "/tmp/property-annotation-contract", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: !fromSource)
    }
}
