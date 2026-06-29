@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-036: Validates that `CharSequence.lineSequence()` resolves
/// through Sema for `String` / `CharSequence` receivers, dispatches to the
/// runtime helper `kk_string_lineSequence_flat` for String receivers, and is classified as non-throwing.
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

    /// Sema should resolve `String.lineSequence()` cleanly without errors.
    @Test func testLineSequenceOnStringResolves() throws {
        let source = """
        fun splitText(s: String) {
            for (line in s.lineSequence()) {
                println(line)
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
                "Expected lineSequence to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let callIDs = allMemberCallExprIDs(
                named: "lineSequence",
                in: ast,
                interner: ctx.interner
            )
            #expect(callIDs.count == 1, "Expected exactly one lineSequence call")
        }
    }

    /// String literal receivers should also resolve through Sema.
    @Test func testLineSequenceOnLiteralResolves() throws {
        let source = """
        fun dump() {
            val items = "a\\nb\\nc".lineSequence()
            for (line in items) {
                println(line)
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
                "Expected literal lineSequence to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    /// Chaining `lineSequence().toList()` should be type-checked without errors,
    /// ensuring the synthetic Sequence<String> return type bridges to standard
    /// sequence operations.
    @Test func testLineSequenceChainsWithToList() throws {
        let source = """
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
                "Expected lineSequence().toList() chain to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    /// The lowered KIR should call the runtime helper `kk_string_lineSequence_flat`,
    /// and the call must be classified as non-throwing.
    @Test func testLineSequenceLowersToRuntimeHelperNonThrowing() throws {
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
            let lineSequenceFlags = try #require(
                throwFlags["kk_string_lineSequence_flat"],
                "Expected kk_string_lineSequence_flat calls to appear in main()"
            )
            #expect(lineSequenceFlags.count == 1)
            #expect(
                lineSequenceFlags.allSatisfy { $0 == false },
                "lineSequence should be classified as non-throwing"
            )
        }
    }
}
