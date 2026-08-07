@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-069: Validates that `CharSequence.split(delimiter, ignoreCase, limit)`
/// resolves through Sema for `String` receivers across all registered overloads.
///
/// The public overloads are loaded from `Stdlib/kotlin/text/StringSplitJoin.kt`;
/// that source delegates to private `__kk_string_split*` bridge stubs.
@Suite
struct StringSplitFunctionTests {
    private func firstExprIDInPath(
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

    private func assertPublicMemberCallIsSourceBacked(
        _ path: String,
        in ctx: CompilationContext,
        memberName: String,
        expectation: String
    ) throws {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprIDInPath(
            in: ast,
            path: path,
            ctx: ctx
        ) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == memberName
        }, "Expected member call to \(memberName)")
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected call binding for \(memberName)"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil,
            "Expected public \(memberName) to resolve to bundled Kotlin source"
        )
        #expect(
            sema.symbols.symbol(chosenCallee)?.declSite != nil,
            "Expected public \(memberName) to have a source declaration"
        )
    }

    @Test func testStringSplitFunctionTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            fun splitCsv(s: String): List<String> {
                return s.split(",")
            }
            """,
            """
            package sample1
            fun splitFirstTwo(s: String): List<String> {
                return s.split(",", limit = 2)
            }
            """,
            """
            package sample2
            fun splitIgnoringCase(s: String): List<String> {
                return s.split("x", ignoreCase = true)
            }
            """,
            """
            package sample3
            fun splitIgnoringCaseWithLimit(s: String): List<String> {
                return s.split("x", ignoreCase = true, limit = 3)
            }
            """,
            """
            package sample4
            fun parts(): List<String> {
                return "a,b,c".split(",")
            }
            """,
            """
            package sample5
            fun parts(s: String): Sequence<String> {
                return s.splitToSequence(",")
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected split overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let expectations: [(String, String, String)] = [
                (paths[0], "split", "Expected split(delimiter) to type-check"),
                (paths[1], "split", "Expected split(delimiter, limit) to type-check"),
                (paths[2], "split", "Expected split(delimiter, ignoreCase) to type-check"),
                (paths[3], "split", "Expected split(delimiter, ignoreCase, limit) to type-check"),
                (paths[4], "split", "Expected split on a String literal to type-check"),
                (paths[5], "splitToSequence", "Expected splitToSequence(delimiter) to type-check"),
            ]
            for (path, memberName, expectation) in expectations {
                try assertPublicMemberCallIsSourceBacked(path, in: ctx, memberName: memberName, expectation: expectation)
            }
        }
    }
}
