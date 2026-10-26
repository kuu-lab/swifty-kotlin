#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct ExplicitTypeArgumentInferencePlaceholderTests {
    private func makeTestContext(_ source: String) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let library = try #require(CompilerOptions.defaultStdlibLibraryPath, "Shared stdlib artifact must be available")
        let manifest = URL(fileURLWithPath: library).appendingPathComponent("manifest.json")
        try #require(FileManager.default.fileExists(atPath: manifest.path), "Shared stdlib artifact must have a manifest")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func infersHolesFromArgumentsAndExpectedTypes() throws {
        let ctx = try makeTestContext("""
        class Box<T, U>(val value: U)
        class PairBox<A, B>(val first: A, val second: B)
        interface Marker
        class Marked : Marker
        class Bounded<T : Marker, U>(val value: T, val label: U)

        fun <A, B> pair(first: A, second: B): PairBox<A, B> = PairBox(first, second)
        fun fromArgument(): String = Box<Int, _>("OK").value
        fun fromExpectedType(): Box<Int, String> = Box<Int, _>("OK")
        fun multipleHoles(): PairBox<String, Long> = PairBox<_, _>("OK", 1L)
        fun genericFunctionHole(): PairBox<Int, String> = pair<Int, _>(1, "OK")
        fun collectionFactoryHoles() = listOf<_>("OK")
        fun mapFactoryHoles() = mapOf<_, _>("answer" to 42)
        fun boundedHole(): Bounded<Marked, String> = Bounded<_, String>(Marked(), "OK")
        """)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let pairCall = try #require(nameRefCallExprID(named: "pair", in: ast, interner: ctx.interner))
        let pairType = try #require(sema.bindings.exprType(for: pairCall))
        guard case let .classType(pairBox) = sema.types.kind(of: pairType) else {
            Issue.record("Expected pair() to return PairBox")
            return
        }
        #expect(pairBox.args == [.invariant(sema.types.intType), .invariant(sema.types.stringType)])

        let listCall = try #require(nameRefCallExprID(named: "listOf", in: ast, interner: ctx.interner))
        guard let listType = sema.bindings.exprType(for: listCall),
              case let .classType(list) = sema.types.kind(of: listType)
        else {
            Issue.record("Expected listOf<_> to return a generic List")
            return
        }
        #expect(list.args == [.invariant(sema.types.stringType)])

        let mapCall = try #require(nameRefCallExprID(named: "mapOf", in: ast, interner: ctx.interner))
        guard let mapType = sema.bindings.exprType(for: mapCall),
              case let .classType(map) = sema.types.kind(of: mapType)
        else {
            Issue.record("Expected mapOf<_, _> to return a generic Map")
            return
        }
        #expect(map.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
    }

    @Test
    func inferredHoleStillHasToSatisfyItsUpperBound() throws {
        let ctx = try makeTestContext("""
        interface Marker
        class Bounded<T : Marker, U>(val value: T, val label: U)
        fun invalid() = Bounded<_, String>("not marked", "label")
        """)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND"
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unresolvedNamedTypeArgumentStillReportsItsName() throws {
        let ctx = try makeTestContext("""
        class Box<T, U>(val value: U)
        fun invalid() = Box<Missing, _>("value")
        """)

        let unresolvedTypes = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(unresolvedTypes.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(unresolvedTypes.first?.message.contains("Missing") == true)
        #expect(unresolvedTypes.allSatisfy { !$0.message.contains("'_'" ) })
    }
}
#endif
