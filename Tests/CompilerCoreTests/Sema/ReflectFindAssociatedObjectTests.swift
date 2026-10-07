#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1324: `kotlin.reflect.findAssociatedObject` is a bundled Kotlin
/// source declaration (`Stdlib/kotlin/reflect/AssociatedObjects.kt`); the
/// compiler expands supported call sites to `__kk_kclass_find_associated_object`
/// via CallLowerer+KClassReflectMemberCalls.swift, so the decl carries no
/// external link name (mirroring the enumValues intrinsic). The synthetic stub
/// registered by `registerSyntheticPropertyInterfaceStubs` remains only as a
/// fallback for compilations without the stdlib.
@Suite
struct ReflectFindAssociatedObjectTests {
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
        #expect(
            sema.symbols.lookupAll(fqName: fqName).count == 1,
            Comment(rawValue: "Expected exactly one findAssociatedObject symbol, got: \(sema.symbols.lookupAll(fqName: fqName))")
        )
        let symbolID = try #require(sema.symbols.lookupAll(fqName: fqName).first)
        let symbol = try #require(sema.symbols.symbol(symbolID))
        let signature = try #require(sema.symbols.functionSignature(for: symbolID))

        #expect(symbol.kind == .function)
        #expect(symbol.visibility == .public)
        #expect(sema.symbols.isSourceBackedSymbol(symbolID))
        #expect(!symbol.flags.contains(.synthetic))
        #expect(symbol.flags.contains(.inlineFunction))
        #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
        #expect(signature.parameterTypes.count == 0)
        #expect(signature.typeParameterSymbols.count == 1)
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(sema.types.renderType(signature.returnType) == "Any?")

        guard let receiverType = signature.receiverType else {
            Issue.record("findAssociatedObject must be a KClass extension function")
            return
        }
        if case .classType(let classType) = sema.types.kind(of: receiverType),
           sema.symbols.symbol(classType.classSymbol)?.fqName == ["kotlin", "reflect", "KClass"].map({ ctx.interner.intern($0) }) {
            // Expected receiver shape.
        } else {
            Issue.record(Comment(rawValue: "Expected KClass receiver, got \(sema.types.renderType(receiverType))"))
        }

        let annotations = sema.symbols.annotations(for: symbolID)
        #expect(
            annotations.contains { $0.annotationFQName.hasSuffix("ExperimentalAssociatedObjects") },
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

    @Test func testFindAssociatedObjectSyntheticFallbackWithoutStdlib() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let path = tempDir.appendingPathComponent("input0.kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(
            path: path,
            contents: Data("""
            package sample0

            annotation class Smoke
            """.utf8)
        )
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }

        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "reflect", "findAssociatedObject"].map { ctx.interner.intern($0) }
        let symbolID = try #require(sema.symbols.lookupAll(fqName: fqName).first)
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.kind == .function)
        #expect(symbol.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: symbolID) == "__kk_kclass_find_associated_object")
    }
}
#endif
