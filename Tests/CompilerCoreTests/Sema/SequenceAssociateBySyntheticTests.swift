@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceAssociateBySyntheticTests {
    @Test func testSequenceAssociateByResolvesInCallExpressions() throws {
        let source = """
        fun buildMap(): Map<Int, String> {
            return sequenceOf("a", "bb", "ccc").associateBy { value ->
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
                Comment(rawValue: "Expected Sequence.associateBy surface to resolve cleanly, got: \(diagnosticSummary)")
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprID = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "associateBy"
            }, "Expected associateBy member call")
            let binding = try #require(sema.bindings.callBinding(for: callExprID))
            let chosenCallee = try #require(binding.chosenCallee)
            #expect(
                sema.symbols.symbol(chosenCallee)?.declSite != nil,
                "Expected Sequence.associateBy call to resolve to the source-backed extension"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }
}
