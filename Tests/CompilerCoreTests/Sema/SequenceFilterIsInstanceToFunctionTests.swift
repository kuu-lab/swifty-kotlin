@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-027: Validates that `Sequence<*>.filterIsInstanceTo<R>` resolves through Sema
/// to the bundled Kotlin source implementation.
@Suite
struct SequenceFilterIsInstanceToFunctionTests {
    @Test func testSequenceFilterIsInstanceToResolvesInSource() throws {
        let source = """
        fun collectInts(values: Sequence<Any>): MutableList<Int> {
            val destination = mutableListOf<Int>()
            return values.filterIsInstanceTo(destination)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Sequence.filterIsInstanceTo to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "filterIsInstanceTo"]
                .map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            #expect(sequenceMembers.contains { sema.symbols.isSourceBackedSymbol($0) })
            #expect(sequenceMembers.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        }
    }
}
