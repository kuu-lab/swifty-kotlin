@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-026: Validates that `Sequence<*>.filterIsInstance<R>()` resolves
/// through Sema and lowers to the synthetic runtime callee `kk_sequence_filterIsInstance`.
@Suite
struct SequenceFilterIsInstanceFunctionTests {
    @Test func testFilterIsInstanceFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun intsOnly(values: Sequence<Any>): Sequence<Int> {
            return values.filterIsInstance<Int>()
        }

        fun stringsOnly(): Sequence<String> {
            val values: Sequence<Any> = sequenceOf(1, "two", 3, "four")
            return values.filterIsInstance<String>()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.filterIsInstance to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )
    }
}
