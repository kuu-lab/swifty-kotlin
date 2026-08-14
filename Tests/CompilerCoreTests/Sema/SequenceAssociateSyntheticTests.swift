@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceAssociateSyntheticTests {
    @Test func testSequenceAssociateResolvesInCallExpressions() throws {
        let source = """
        fun buildMap(): Map<Int, Int> {
            return sequenceOf(1, 2, 3).associate { value ->
                (value % 2) to (value * 10)
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
                Comment(rawValue: "Expected Sequence.associate surface to resolve cleanly, got: \(diagnosticSummary)")
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprID = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "associate"
            }, "Expected associate member call")
            let binding = try #require(sema.bindings.callBinding(for: callExprID))
            let chosenCallee = binding.chosenCallee
            #expect(
                sema.symbols.symbol(chosenCallee)?.declSite != nil,
                "Expected Sequence.associate call to resolve to the source-backed extension"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }

    @Test func testSequenceAssociateToResolvesSourceBackedDestinationCall() throws {
        let source = """
        fun fill(destination: MutableMap<String, Int>): MutableMap<String, Int> {
            val source = sequenceOf("a", "bb", "ccc")
            source.associateTo(destination) { value -> value to value.length }
            return destination
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprID = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "associateTo"
            }, "Expected associateTo member call")
            let binding = try #require(sema.bindings.callBinding(for: callExprID))
            let chosenCallee = binding.chosenCallee
            #expect(
                sema.symbols.symbol(chosenCallee)?.declSite != nil,
                "Expected Sequence.associateTo to resolve to the source-backed extension"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }
}
