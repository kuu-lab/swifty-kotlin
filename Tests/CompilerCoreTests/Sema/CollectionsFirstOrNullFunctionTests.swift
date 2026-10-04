#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-COL-FN-074: Validates that `firstOrNull` resolves through Sema for the
/// collection receivers wired through the standard aggregate / HOF infrastructure
/// — `List<T>` / `Set<T>` (no-arg), source-backed `List<T>` (predicate HOF),
/// `Range` (no-arg and predicate overloads), and `Array<T>` (no-arg and
/// predicate overloads, via bundled Kotlin source).
/// Array calls are source-backed and therefore do not require an array HOF runtime link.
@Suite
struct CollectionsFirstOrNullFunctionTests {
    @Test func testFirstOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun maybeFirstList(xs: List<Int>): Int? {
            return xs.firstOrNull()
        }

        fun maybeFirstListMatching(xs: List<Int>): Int? {
            return xs.firstOrNull { it > 5 }
        }

        fun maybeFirstSet(xs: Set<Int>): Int? {
            return xs.firstOrNull()
        }

        fun maybeFirstRange(): Int? {
            return (1..10).firstOrNull()
        }

        fun maybeFirstRangeMatching(): Int? {
            return (1..10).firstOrNull { it > 5 }
        }

        fun maybeFirstArray(xs: Array<Int>): Int? {
            return xs.firstOrNull()
        }

        fun maybeFirstArrayMatching(xs: Array<Int>): Int? {
            return xs.firstOrNull { it > 5 }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected firstOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
    }
}
#endif
