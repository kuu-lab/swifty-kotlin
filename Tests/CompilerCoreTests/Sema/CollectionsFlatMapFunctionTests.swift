#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-COL-FN-075: Validates that `flatMap` resolves through Sema for the
/// primary collection receivers — `List<T>` (basic, cross-type), `Map<K,V>`,
/// and `Set<T>` (via the shared iterable path).
@Suite
struct CollectionsFlatMapFunctionTests {
    @Test func testFlatMapFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun expand(xs: List<Int>): List<Int> {
            return xs.flatMap { listOf(it, it * 2) }
        }

        fun test(xs: List<String>): List<String> {
            return xs.flatMap { listOf(it, it.uppercase()) }
        }

        fun toLengths(xs: List<String>): List<Int> {
            return xs.flatMap { listOf(it.length, it.length * 2) }
        }

        fun expandMap(m: Map<String, Int>): List<String> {
            return m.flatMap { (key, value) -> listOf(key, value.toString()) }
        }

        fun expandSet(xs: Set<Int>): List<Int> {
            return xs.flatMap { listOf(it, it * 10) }
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected flatMap to type-check, got: \(errors.map { $0.message })"
        )
    }
}
#endif
