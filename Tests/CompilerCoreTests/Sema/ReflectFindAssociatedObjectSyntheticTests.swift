#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectFindAssociatedObjectSyntheticTests {
    @Test func testFindAssociatedObject() throws {
        let sources = [
            """
            package sample0

            annotation class Smoke
            """,
            """
            package sample1

            import kotlin.reflect.KClass
            import kotlin.reflect.findAssociatedObject

            annotation class Binding

            fun find(kclass: KClass<*>): Any? = kclass.findAssociatedObject<Binding>()
            """,
            """
            package sample2

            import kotlin.reflect.ExperimentalAssociatedObjects
            import kotlin.reflect.KClass
            import kotlin.reflect.findAssociatedObject

            annotation class Binding

            @OptIn(ExperimentalAssociatedObjects::class)
            fun find(kclass: KClass<*>): Any? = kclass.findAssociatedObject<Binding>()
            """,
        ]

        let ctx = makeContextFromSources(sources)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }

        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "reflect", "findAssociatedObject"].map { ctx.interner.intern($0) }
        let symbolID = try #require(sema.symbols.lookupAll(fqName: fqName).first)
        let symbol = try #require(sema.symbols.symbol(symbolID))
        let signature = try #require(sema.symbols.functionSignature(for: symbolID))

        #expect(symbol.kind == .function)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.flags.contains(.inlineFunction))
        #expect(sema.symbols.externalLinkName(for: symbolID) == "__kk_kclass_find_associated_object")
        #expect(signature.parameterTypes.count == 0)
        #expect(signature.typeParameterSymbols.count == 1)
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(sema.types.renderType(signature.returnType) == "Any?")

        guard let receiverType = signature.receiverType else {
            Issue.record("findAssociatedObject must be a KClass extension function")
            return
        }
        if case .kClassType = sema.types.kind(of: receiverType) {
            // Expected receiver shape.
        } else {
            Issue.record(Comment(rawValue: "Expected KClass receiver, got \(sema.types.renderType(receiverType))"))
        }

        let annotations = sema.symbols.annotations(for: symbolID)
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.reflect.ExperimentalAssociatedObjects" },
            Comment(rawValue: "Expected findAssociatedObject to require ExperimentalAssociatedObjects opt-in, got: \(annotations)")
        )

        let paths = ctx.sourceManager.fileIDs().filter { ctx.sourceManager.origin(of: $0) == .user }
        #expect(paths.count == 3)

        let optInDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        let sample1Path = paths[1]
        let sample1OptInDiagnostics = optInDiagnostics.filter { $0.primaryRange?.start.file == sample1Path }
        let sample2Path = paths[2]
        let sample2OptInDiagnostics = optInDiagnostics.filter { $0.primaryRange?.start.file == sample2Path }

        #expect(sample1OptInDiagnostics.count == 1, Comment(rawValue: "Expected findAssociatedObject usage to require opt-in, got: \(ctx.diagnostics.diagnostics)"))
        #expect(sample2OptInDiagnostics.isEmpty, Comment(rawValue: "Expected @OptIn to satisfy findAssociatedObject usage, got: \(ctx.diagnostics.diagnostics)"))
    }
}
#endif
