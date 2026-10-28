import Foundation
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct TypedAnnotationMetadataTests {
    @Test func annotatedElementReadsMaterializeTypedInstances() throws {
        let context = makeContextFromSource("""
        import kotlin.reflect.KAnnotatedElement
        fun read(element: KAnnotatedElement): List<Annotation> = element.annotations
        """)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let body = try findKIRFunctionBody(named: "read", in: #require(context.kir), interner: context.interner)
        let calls = kirCalls(in: body)
        for name in ["__kk_kclass_get_annotations_typed", "__kk_kcallable_get_annotations_typed"] {
            let call = try #require(calls.first { context.interner.resolve($0.callee) == name })
            #expect(call.arguments.count == 1)
            #expect(call.canThrow)
        }
        #expect(!calls.contains {
            ["__kk_kclass_get_annotations", "__kk_kcallable_get_metadata"].contains(context.interner.resolve($0.callee))
        })
        // Source implementations still dispatch through their interface getter.
        #expect(body.contains {
            guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = $0,
                  case .itableDynamic = dispatch else { return false }
            return true
        })
    }

    @Test func factoryLinkNamesRoundTripWithoutChangingLegacyMetadata() {
        let annotations = [MetadataAnnotationRecord(annotationFQName: "Legacy"),
                           MetadataAnnotationRecord(annotationFQName: "private.Named", arguments: ["value=1"],
                                                    factoryLinkName: "kk_fn_producer_annotation_factory_123")]
        let encoded = MetadataEncoder().serialize([MetadataRecord(kind: .class, fqName: "Tagged", annotations: annotations)])
        #expect(MetadataDecoder().decode(encoded).first?.annotations == annotations)
    }

    @Test func constructorTokensSurviveTheFrontendSnapshot() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        package factorycases
        annotation class Named(val value: String, val codes: IntArray = [1, 2])
        @Named(value = "x\\n" + "y", codes = [3, 4]) class Tagged
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            let snapshot = try JSONDecoder().decode(ASTArenaSnapshot.self,
                                                    from: JSONEncoder().encode(ast.arena.snapshot()))
            let reconstructed = ASTArena(snapshot: snapshot)
            let tagged = try #require(reconstructed.declarations().compactMap { decl -> ClassDecl? in
                guard case let .classDecl(value) = decl,
                      context.interner.resolve(value.name) == "Tagged" else { return nil }
                return value
            }.first)
            #expect(tagged.annotations.first?.constructionTokens?.contains(where: { $0.kind == .symbol(.lBracket) }) == true)
            let sema = try #require(context.sema)
            let symbol = try #require(sema.symbols.lookup(fqName: [context.interner.intern("factorycases"), context.interner.intern("Tagged")]))
            let record = try #require(sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "factorycases.Named" })
            let factory = try #require(record.factorySymbol)
            #expect(sema.bindings.annotationFactoryExpressions[factory] != nil)
            let records = MetadataEncoder().buildRecords(symbols: sema.symbols, types: sema.types, moduleName: "Factories",
                interner: context.interner, functionLinkNames: [factory: "kk_fn_factory_actual_link"])
            #expect(records.first { $0.fqName == "factorycases.Tagged" }?.annotations.first {
                $0.annotationFQName == "factorycases.Named"
            }?.factoryLinkName == "kk_fn_factory_actual_link")
        }
    }

    @Test func forwardConstantsAndPrivateInlineAnnotationsRemainValid() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        annotation class Tag(val x: Int)
        @Tag(A) class C
        const val B: Int = 1
        const val A: Int = B
        private annotation class PrivateTag
        @PrivateTag inline fun marked() {}
        typealias MyInt = Int
        class Numbers(vararg val values: MyInt)
        fun values(): IntArray = Numbers(1, 2).values
        class Holder { annotation class Nested(val value: String = "nested") }
        @Holder.Nested class NestedTagged
        fun nested(): Holder.Nested = Holder.Nested("explicit")
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            var links: [SymbolID: String] = [:]
            for owner in [["Tag"], ["Holder", "Nested"]] {
                for name in ["equals", "hashCode", "toString"] {
                    let members = sema.symbols.lookupAll(fqName: (owner + [name]).map(context.interner.intern))
                    let member = try #require(members.first { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true })
                    links[member] = "kk_annotation_" + (owner + [name]).joined(separator: "_")
                }
            }
            let records = MetadataEncoder().buildRecords(symbols: sema.symbols, types: sema.types,
                moduleName: "AnnotationLibrary", interner: context.interner, functionLinkNames: links, includeSynthetic: false)
            for owner in [["Tag"], ["Holder", "Nested"]] {
                for name in ["equals", "hashCode", "toString"] {
                    let member = try #require(records.first { $0.fqName == (owner + [name]).joined(separator: ".") })
                    #expect(member.externalLinkName == "kk_annotation_" + (owner + [name]).joined(separator: "_"))
                    #expect(records.first { $0.fqName == owner.joined(separator: ".") }?.vtableSlots?.contains(name) == true)
                }
            }
            #expect(!records.contains { $0.fqName == "PrivateTag" || $0.fqName.hasPrefix("PrivateTag.") })
        }
    }

    @Test func annotationArrayLiteralsIgnoreUserFactoryNames() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        fun intArrayOf(vararg values: Int): IntArray = kotlin.intArrayOf(*values)
        fun arrayOf(vararg values: String): Array<out String> = kotlin.arrayOf(*values)
        annotation class Tag(val ints: IntArray, val names: Array<String>)
        @Tag([1, 2], ["a", "b"]) class Tagged
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test func annotationConstructionPreservesUnvalidatedAndNestedOptInChecks() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR) annotation class Marker
        @Marker annotation class ExperimentalTag
        @OptIn(Marker::class) annotation class Outer(val nested: ExperimentalTag)
        @ExperimentalTag fun rootUsage() {}
        @Outer(ExperimentalTag()) fun nestedUsage() {}
        @OptIn(Marker::class) @ExperimentalTag fun safeRootUsage() {}
        @OptIn(Marker::class) @Outer(ExperimentalTag()) fun safeNestedUsage() {}
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            let diagnostics = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            #expect(diagnostics.count == 2, "\(context.diagnostics.diagnostics)")
            #expect(diagnostics.allSatisfy { $0.message.contains("Marker") })
            #expect(context.diagnostics.diagnostics.filter { $0.code != "KSWIFTK-SEMA-OPT-IN" }.isEmpty)
        }
    }

    @Test func nonconstantAnnotationArgumentsAndNonannotationLookupAreRejected() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        import kotlin.reflect.full.findAnnotation
        annotation class Named(val value: String)
        fun value(): String = "not constant"
        @Named(value()) class Tagged
        @Retention(AnnotationRetention.SOURCE) annotation class SourceName(val value: String)
        @Retention(AnnotationRetention.BINARY) annotation class BinaryName(val value: String)
        @SourceName(value()) @BinaryName(value()) class HiddenTagged
        annotation class DefaultName(val value: String = value())
        enum class E { A }
        @Named("${E.A}") class InterpolatedEnum
        fun main() { Tagged::class.findAnnotation<Int>() }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            #expect(context.diagnostics.diagnostics.contains { $0.message.contains("compile-time constants") })
            let lookupOffset = try #require(source.range(of: "Tagged::class.findAnnotation<Int>()")).lowerBound
            let expectedOffset = source[..<lookupOffset].utf8.count
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND"
                    && $0.primaryRange?.start.offset == expectedOffset
            })
            #expect(context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST" }.count >= 5)
        }
    }
}
