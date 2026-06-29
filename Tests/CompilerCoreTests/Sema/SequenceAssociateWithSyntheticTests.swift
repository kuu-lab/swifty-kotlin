@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceAssociateWithSyntheticTests {
    @Test func testSequenceAssociateWithResolvesInCallExpressions() throws {
        let source = """
        fun buildMap(): Map<String, Int> {
            return sequenceOf("a", "bb", "ccc").associateWith { value ->
                value.length
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                Comment(rawValue: "Expected Sequence.associateWith surface to resolve cleanly, got: \(diagnosticSummary)")
            )

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "associateWith"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(links.contains("kk_sequence_associateWith"))
        }
    }
}
