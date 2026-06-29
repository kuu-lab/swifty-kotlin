@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-006: Validates that `Sequence<T>.associateBy(keySelector)`
/// resolves through Sema, returning a `Map<K, T>` keyed by the selector result.
/// Runtime link name involved: `kk_sequence_associateBy`.
@Suite
struct SequenceAssociateByFunctionTests {
    @Test func testSequenceAssociateByResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun lengthIndexed(): Map<Int, String> {
            return sequenceOf("a", "bb", "ccc").associateBy { value ->
                value.length
            }
        }

        fun firstCharIndexed(words: Sequence<String>): Map<Char, String> {
            return words.associateBy { it[0] }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.associateBy to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )
    }
}
