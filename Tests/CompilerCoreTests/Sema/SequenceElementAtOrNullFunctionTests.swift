@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-022: Validates that `Sequence<T>.elementAtOrNull(index)` resolves
/// through Sema and is wired to the runtime entry point `kk_sequence_elementAtOrNull`.
/// The terminal operator returns the element at the given index, or `null` when the
/// index is out of range, without throwing.
final class SequenceElementAtOrNullFunctionTests: XCTestCase {
    func testSequenceElementAtOrNullResolvesAndReturnsNullableElement() throws {
        let ctx = makeContextFromSource("""
        fun maybeSecond(values: Sequence<Int>): Int? {
            return values.elementAtOrNull(1)
        }

        fun maybeFromGenerated(): String? {
            return sequenceOf("alpha", "beta", "gamma").elementAtOrNull(0)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Sequence.elementAtOrNull(index) to type-check, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "elementAtOrNull"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_elementAtOrNull"),
            "Expected Sequence.elementAtOrNull synthetic member to link to kk_sequence_elementAtOrNull, found: \(links)"
        )
    }
}
