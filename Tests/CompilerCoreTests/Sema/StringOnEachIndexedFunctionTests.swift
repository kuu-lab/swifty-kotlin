#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-040: Validates that `String.onEachIndexed(action)` resolves
/// through Sema. After KSP-410 it is bundled Kotlin source (StringHOF.kt);
/// see StringSyntheticMemberLinkTests for the "carries no C external link"
/// check.
@Suite
struct StringOnEachIndexedFunctionTests {
    @Test
    func testStringOnEachIndexedResolvesAndReturnsString() throws {
        let source = """
        fun logIndexedChars(value: String): String {
            return value.onEachIndexed { i, c -> print("$i:$c") }
        }

        fun logLiteralIndexed(): String {
            return "hello".onEachIndexed { index, ch -> print(index) }
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
                "Expected String.onEachIndexed to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var callIDs: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "onEachIndexed"
                else { continue }
                callIDs.append(exprID)
            }
            #expect(callIDs.count == 2, "Expected two String.onEachIndexed call sites")
            for callID in callIDs {
                let exprType = try #require(sema.bindings.exprType(for: callID))
                #expect(
                    exprType == sema.types.stringType,
                    "String.onEachIndexed should be typed as String"
                )
            }
        }
    }

    // KSP-410: String.onEachIndexed is bundled Kotlin source (StringHOF.kt),
    // so it no longer registers as a synthetic extension with a C external
    // link name and no longer lowers to a single flat runtime call site.
    // See StringSyntheticMemberLinkTests.testStringHOFMembersAreBundledKotlin
    // for the "carries no C external link" coverage.
}
#endif
