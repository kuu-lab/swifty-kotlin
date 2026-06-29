@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-044: Validates that `kotlin.sequences.Sequence<T>.forEach`
/// resolves through Sema and is wired to the runtime bridge.
/// Runtime link name: `kk_sequence_forEach`.
@Suite
struct SequenceForEachFunctionTests {
    @Test func testSequenceForEachResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun printAll(values: Sequence<Int>) {
            values.forEach { value -> println(value) }
        }

        fun printFromLiteral() {
            sequenceOf(1, 2, 3).forEach { value -> println(value) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.forEach to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let sema = try #require(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "forEach"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.contains("kk_sequence_forEach"),
            Comment(rawValue: "Expected Sequence.forEach to link to kk_sequence_forEach, got: \(links)")
        )
    }
}
