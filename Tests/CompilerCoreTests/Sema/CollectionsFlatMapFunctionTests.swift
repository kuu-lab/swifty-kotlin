#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-COL-FN-075: Validates that `flatMap` resolves through Sema for the
/// primary collection receivers — `List<T>` (basic, cross-type), `Map<K,V>`,
/// and `Set<T>` (via the shared iterable path).
/// Runtime link names involved: `kk_list_flatMap`, `kk_map_flatMap`.
@Suite
struct CollectionsFlatMapFunctionTests {
    @Test func testFlatMapFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun expand(xs: List<Int>): List<Int> {
            return xs.flatMap { listOf(it, it * 2) }
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testFlatMapReturnTypeIsListOfElement() throws {
        let ctx = makeContextFromSource("""
        fun test(xs: List<String>): List<String> {
            return xs.flatMap { listOf(it, it.uppercase()) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected flatMap result assignable to List<String>, got: \(errors.map { $0.message })")
    }

    @Test func testFlatMapCrossTypeTransform() throws {
        let ctx = makeContextFromSource("""
        fun toLengths(xs: List<String>): List<Int> {
            return xs.flatMap { listOf(it.length, it.length * 2) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected cross-type flatMap to type-check, got: \(errors.map { $0.message })")
    }

    @Test func testFlatMapOnMapResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun expand(m: Map<String, Int>): List<String> {
            return m.flatMap { (key, value) -> listOf(key, value.toString()) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected Map.flatMap to type-check, got: \(errors.map { $0.message })")
    }

    @Test func testFlatMapOnSetResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun expand(xs: Set<Int>): List<Int> {
            return xs.flatMap { listOf(it, it * 10) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected Set.flatMap to type-check, got: \(errors.map { $0.message })")
    }
}
#endif
