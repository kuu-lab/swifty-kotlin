@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-001: Validates that `CharSequence.all(predicate)` resolves
/// through Sema for String receivers. After KSP-410 it is bundled Kotlin
/// source (StringHOF.kt); see StringSyntheticMemberLinkTests for the
/// "carries no C external link" check.
@Suite
struct StringAllFunctionTests {
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

    /// Sema should accept `String.all { predicate }` with a `(Char) -> Boolean`
    /// lambda and resolve the result type to `Boolean`.
    @Test func testStringAllResolvesAndReturnsBoolean() throws {
        let source = """
        fun allDigits(value: String): Boolean {
            return value.all { c -> c.isDigit() }
        }

        fun allUppercase(): Boolean {
            return "HELLO".all { it.isUpperCase() }
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
                "Expected String.all to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "all", in: ast, interner: ctx.interner)
            #expect(callIDs.count == 2, "Expected two String.all call sites")
            for callID in callIDs {
                let exprType = try #require(sema.bindings.exprType(for: callID))
                #expect(
                    exprType == sema.types.booleanType,
                    "String.all should be typed as Boolean"
                )
            }
        }
    }

    // KSP-410: String.all is bundled Kotlin source (StringHOF.kt), so it no
    // longer registers as a synthetic extension with a C external link name
    // and no longer lowers to a single flat runtime call site. See
    // StringSyntheticMemberLinkTests.testStringHOFMembersAreBundledKotlin for
    // the "carries no C external link" coverage.
}
