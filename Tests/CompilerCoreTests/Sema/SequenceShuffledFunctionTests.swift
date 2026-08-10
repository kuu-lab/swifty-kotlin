@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-106: Sema coverage for `kotlin.sequences.Sequence<T>.shuffled`.
///
/// Verifies that both `shuffled()` and `shuffled(random: Random)` resolve to
/// their runtime entries and preserve the receiver's `Sequence<T>` return type.
@Suite
struct SequenceShuffledFunctionTests {
    // MARK: - Path-aware expression search helper

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    @Test func testSequenceShuffled() throws {
        let sources: [String] = [
            """
            package sample0

            fun shuffledValues(): Sequence<Int> {
                return sequenceOf(1, 2, 3, 4).shuffled()
            }
            """,
            """
            package sample1
            import kotlin.random.Random

            fun shuffledValues(random: Random): Sequence<Int> {
                return sequenceOf(1, 2, 3, 4).shuffled(random)
            }
            """,
            """
            package sample2

            fun shuffled(values: Sequence<String>): Sequence<String> = values.shuffled()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Sequence.shuffled surfaces to type-check cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let memberFQName = ["kotlin", "sequences", "Sequence", "shuffled"]
                .map { interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            let expectedLinks = Set(["kk_sequence_shuffled", "kk_sequence_shuffled_random"])
            #expect(
                expectedLinks.isSubset(of: links),
                "Expected \(expectedLinks.sorted()) in resolved link names \(links.sorted())"
            )

            let sample2Path = paths[2]
            let functionSymbol = try #require(
                sema.symbols.lookup(fqName: [interner.intern("sample2"), interner.intern("shuffled")])
            )
            let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))
            let sequenceSymbol = try #require(sema.symbols.lookup(
                fqName: ["kotlin", "sequences", "Sequence"].map { interner.intern($0) }
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
            let callExpr = try #require(firstExprID(in: ast, path: sample2Path, ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return interner.resolve(callee) == "shuffled"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_sequence_shuffled"
            )
        }
    }
}
