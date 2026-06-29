@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-024: Validates that `kotlin.sequences.Sequence<T>.filterIndexed`
/// resolves through Sema and is wired to the runtime bridge.
/// Runtime link name: `kk_sequence_filterIndexed`.
@Suite
struct SequenceFilterIndexedFunctionTests {
    @Test func testSequenceFilterIndexedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickIndexed(values: Sequence<Int>): Sequence<Int> {
            return values.filterIndexed { index, value -> index % 2 == 0 || value > 10 }
        }

        fun pickIndexedFromGenerator(): Sequence<Int> {
            return sequenceOf(10, 20, 30, 40).filterIndexed { index, _ -> index < 3 }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.filterIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let sema = try #require(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "filterIndexed"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.contains("kk_sequence_filterIndexed"),
            Comment(rawValue: "Expected Sequence.filterIndexed to link to kk_sequence_filterIndexed, got: \(links)")
        )
    }
}
