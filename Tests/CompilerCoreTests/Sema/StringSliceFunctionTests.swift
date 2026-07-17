#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-068: Validates that `kotlin.text.String.slice` resolves
/// through Sema for both the IntRange overload and the Iterable<Int> overload.
/// Runtime link names involved: `kk_string_slice_range`, `kk_string_slice_iterable`.
@Suite
struct StringSliceFunctionTests {
    @Test func testSliceRangeOverloadResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun sliceByRange(s: String): String {
            return s.slice(1..3)
        }

        fun sliceByUntil(s: String): String {
            return s.slice(0 until 5)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected slice(IntRange) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSliceIterableOverloadResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun sliceByList(s: String): String {
            return s.slice(listOf(0, 2, 4))
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected slice(Iterable<Int>) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSliceViaVariableResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun sliceViaVar(s: String): String {
            val r = 1..3
            return s.slice(r)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected slice via variable to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
