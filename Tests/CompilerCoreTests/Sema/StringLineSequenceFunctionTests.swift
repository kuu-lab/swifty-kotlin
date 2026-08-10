#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-036: Validates that `CharSequence.lineSequence()` resolves
/// through Sema for `String` / `CharSequence` receivers via bundled Kotlin source.
@Suite
struct StringLineSequenceFunctionTests {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            results.append(exprID)
        }
        return results
    }

    @Test func testLineSequenceResolvesInSource() throws {
        let source = """
        fun splitText(s: String) {
            for (line in s.lineSequence()) {
                println(line)
            }
        }

        fun dump() {
            val items = "a\\nb\\nc".lineSequence()
            for (line in items) {
                println(line)
            }
        }

        fun gather(s: String): List<String> {
            return s.lineSequence().toList()
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
                "Expected lineSequence to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let callIDs = allMemberCallExprIDs(
                named: "lineSequence",
                in: ast,
                interner: ctx.interner
            )
            #expect(callIDs.count == 3, "Expected three lineSequence calls")
        }
    }

    /// The lowered KIR should not call the legacy runtime helper after migration
    /// to bundled Kotlin source.
    @Test func testLineSequenceDoesNotLowerToLegacyRuntimeHelper() throws {
        let source = """
        fun main() {
            val text = "a\\nb\\nc"
            for (line in text.lineSequence()) {
                println(line)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(
                named: "main",
                in: module,
                interner: ctx.interner
            )
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_string_lineSequence"] == nil)
            #expect(throwFlags["kk_string_lineSequence_flat"] == nil)
            #expect(throwFlags["kk_string_lines"] == nil)
            #expect(throwFlags["kk_string_lines_flat"] == nil)
        }
    }
}
#endif
