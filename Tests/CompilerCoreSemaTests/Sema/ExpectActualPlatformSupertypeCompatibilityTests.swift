#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpectActualPlatformSupertypeCompatibilityTests {
    @Test
    func testActualClassAllowsAdditionalSupertypeButPreservesExpectedContract() throws {
        let ctx = makeContextFromSourcesWithoutStdlib([
            """
            package sample.kmp
            expect interface Contract
            expect class Impl : Contract
            expect interface GenericContract<T>
            expect class GenericImpl<T> : GenericContract<T>
            expect interface MissingContract
            expect class MissingImpl : MissingContract
            """,
            """
            package sample.kmp
            actual interface Contract
            interface PlatformOnly
            actual class Impl : Contract, PlatformOnly
            actual interface GenericContract<T>
            actual class GenericImpl<T> : GenericContract<Int>, PlatformOnly
            actual interface MissingContract
            actual class MissingImpl : PlatformOnly
            """,
        ])

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let unresolvedErrors = errors.filter { $0.code == "KSWIFTK-MPP-UNRESOLVED" }
        #expect(
            unresolvedErrors.count == 2,
            "Only the missing and mismatched common supertypes should remain unresolved: \(errors)"
        )

        let sema = try #require(ctx.sema)
        func nominalSymbols(named name: String) -> [SemanticSymbol] {
            sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("sample"),
                ctx.interner.intern("kmp"),
                ctx.interner.intern(name),
            ]).compactMap { sema.symbols.symbol($0) }
        }

        let implSymbols = nominalSymbols(named: "Impl")
        let expectImpl = try #require(implSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualImpl = try #require(implSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectImpl.id) == actualImpl.id)

        let expectGenericImpl = try #require(
            nominalSymbols(named: "GenericImpl").first { $0.flags.contains(.expectDeclaration) }
        )
        #expect(sema.symbols.actualSymbol(for: expectGenericImpl.id) == nil)

        let expectMissingImpl = try #require(
            nominalSymbols(named: "MissingImpl").first { $0.flags.contains(.expectDeclaration) }
        )
        #expect(sema.symbols.actualSymbol(for: expectMissingImpl.id) == nil)
    }

    // KUU-4178 / KUU-4373: an expect class may omit the supertype constructor
    // arguments because the actual declaration provides the delegation —
    // kotlinx's `UndispatchedCoroutine<in T> : ScopeCoroutine<T>` relies on it.
    @Test
    func testExpectClassMayOmitSupertypeConstructorArguments() throws {
        let ctx = makeContextFromSourcesWithoutStdlib([
            """
            package test
            internal abstract class ScopeCoroutine<in T>(val context: Int, val uCont: Int)
            internal expect class UndispatchedCoroutine<in T>(
                context: Int,
                uCont: Int
            ) : ScopeCoroutine<T>
            """,
            """
            package test
            internal actual class UndispatchedCoroutine<in T> actual constructor(
                context: Int,
                uCont: Int
            ) : ScopeCoroutine<T>(context, uCont)
            """,
        ])

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expect class supertype constructor omission should be accepted: \(errors)"
        )
    }

    private func makeContextFromSourcesWithoutStdlib(_ sources: [String]) -> CompilationContext {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputs = sources.indices.map { index in
            tempDirectory.appendingPathComponent("input\(index).kt").path
        }
        let ctx = makeCompilationContext(inputs: inputs, includeStdlib: false)
        for (path, source) in zip(inputs, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        return ctx
    }
}
#endif
