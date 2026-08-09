#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-068: Validates that `kotlin.text.String.slice` resolves
/// through Sema for both the IntRange overload and the Iterable<Int> overload.
/// After KSP-406 both overloads are bundled Kotlin source (StringSubstringSlice.kt)
/// with no String-specific runtime helper.
@Suite
struct StringSliceFunctionTests {
    @Test func testSliceResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun sliceByRange(s: String): String {
            return s.slice(1..3)
        }

        fun sliceByUntil(s: String): String {
            return s.slice(0 until 5)
        }

        fun sliceByList(s: String): String {
            return s.slice(listOf(0, 2, 4))
        }

        fun sliceViaVar(s: String): String {
            val r = 1..3
            return s.slice(r)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.slice(...) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
