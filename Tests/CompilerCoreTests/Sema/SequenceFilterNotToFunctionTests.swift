@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-030: Validates that `Sequence<T>.filterNotTo` resolves through Sema
/// to the bundled Kotlin source implementation.
@Suite
struct SequenceFilterNotToFunctionTests {
    @Test func testSequenceFilterNotToResolvesInSource() throws {
        let source = """
        fun rejectEvens(values: Sequence<Int>): MutableList<Int> {
            val destination = mutableListOf<Int>()
            return values.filterNotTo(destination) { value -> value % 2 == 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Sequence.filterNotTo to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "filterNotTo"]
                .map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            #expect(sequenceMembers.contains { sema.symbols.isSourceBackedSymbol($0) })
            #expect(sequenceMembers.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        }
    }
}
