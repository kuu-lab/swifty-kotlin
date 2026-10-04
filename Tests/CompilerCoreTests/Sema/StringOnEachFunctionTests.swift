#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-039: Validates that `String.onEach(action)` resolves
/// through Sema. After KSP-410 it is bundled Kotlin source (StringHOF.kt);
/// see StringSyntheticMemberLinkTests for the "carries no C external link"
/// check.
@Suite
struct StringOnEachFunctionTests {
    @Test
    func testStringOnEachResolvesAndReturnsString() throws {
        let source = """
        fun logChars(value: String): String {
            return value.onEach { c -> print(c) }
        }

        fun logLiteral(): String {
            return "hello".onEach { print(it) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected String.onEach to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var callIDs: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "onEach"
                else { continue }
                callIDs.append(exprID)
            }
            #expect(callIDs.count == 2, "Expected two String.onEach call sites")
            for callID in callIDs {
                let exprType = try #require(sema.bindings.exprType(for: callID))
                #expect(
                    exprType == sema.types.stringType,
                    "String.onEach should be typed as String"
                )
            }
        }
    }

    // KSP-410: String.onEach is bundled Kotlin source (StringHOF.kt), so it
    // no longer registers as a synthetic extension with a C external link
    // name and no longer lowers to a single flat runtime call site. See
    // StringSyntheticMemberLinkTests.testStringHOFMembersAreBundledKotlin for
    // the "carries no C external link" coverage.
}
#endif
