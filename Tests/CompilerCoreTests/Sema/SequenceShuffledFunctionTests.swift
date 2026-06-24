@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-106: Sema coverage for `kotlin.sequences.Sequence<T>.shuffled`.
///
/// Verifies that both `shuffled()` and `shuffled(random: Random)` resolve to
/// their runtime entries and preserve the receiver's `Sequence<T>` return type.
@Suite
struct SequenceShuffledFunctionTests {
    @Test func testSequenceShuffledResolvesToRuntimeABI() throws {
        try assertSequenceMemberResolves(
            source: """
            fun shuffledValues(): Sequence<Int> {
                return sequenceOf(1, 2, 3, 4).shuffled()
            }
            """,
            memberName: "shuffled",
            expectedLinkName: "kk_sequence_shuffled",
            diagnosticContext: "Sequence.shuffled"
        )
    }

    @Test func testSequenceShuffledWithRandomResolvesToRuntimeABI() throws {
        try assertSequenceMemberResolves(
            source: """
            import kotlin.random.Random

            fun shuffledValues(random: Random): Sequence<Int> {
                return sequenceOf(1, 2, 3, 4).shuffled(random)
            }
            """,
            memberName: "shuffled",
            expectedLinkName: "kk_sequence_shuffled_random",
            diagnosticContext: "Sequence.shuffled(random)"
        )
    }

    @Test func testSequenceShuffledReturnsSequenceOfReceiverElement() throws {
        let source = """
        fun shuffled(values: Sequence<String>): Sequence<String> = values.shuffled()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Sequence.shuffled to type-check, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let functionSymbol = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("shuffled")])
            )
            let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))
            let sequenceSymbol = try #require(sema.symbols.lookup(
                fqName: ["kotlin", "sequences", "Sequence"].map { ctx.interner.intern($0) }
            ))

            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected shuffled() to return Sequence<String>")
                return
            }
            #expect(returnClassType.classSymbol == sequenceSymbol)
            let returnArg: TypeID
            switch try #require(returnClassType.args.first) {
            case let .invariant(arg), let .out(arg):
                returnArg = arg
            case .in, .star:
                Issue.record("Expected shuffled() to return Sequence<String>")
                return
            }
            #expect(returnArg == sema.types.stringType)

            // Also verify that the chosen callee links to kk_sequence_shuffled.
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "shuffled"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_sequence_shuffled"
            )
        }
    }
}
