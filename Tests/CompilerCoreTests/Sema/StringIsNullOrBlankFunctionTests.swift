@testable import CompilerCore
import Foundation
import Testing

/// Verifies CharSequence?.isNullOrBlank() (STDLIB-TEXT-FN-032) resolves cleanly
/// in Sema through bundled Kotlin source.
@Suite
struct StringIsNullOrBlankFunctionTests {
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

    /// Sema should accept `String?.isNullOrBlank()` and return Boolean.
    @Test func testIsNullOrBlankOnNullableStringResolvesToBoolean() throws {
        let source = """
        fun classify(value: String?): Boolean {
            return value.isNullOrBlank()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected isNullOrBlank to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "isNullOrBlank", in: ast, interner: ctx.interner)
            #expect(callIDs.count == 1)
            let exprType = try #require(sema.bindings.exprTypes[callIDs[0]])
            #expect(
                exprType == sema.types.booleanType,
                "isNullOrBlank should be typed as Boolean"
            )
        }
    }

    /// Receiver typed as non-null String should still resolve isNullOrBlank.
    @Test func testIsNullOrBlankOnNonNullStringResolves() throws {
        let source = """
        fun classify(value: String): Boolean {
            return value.isNullOrBlank()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected isNullOrBlank on non-null String to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "isNullOrBlank", in: ast, interner: ctx.interner)
            #expect(callIDs.count == 1)
            let exprType = try #require(sema.bindings.exprTypes[callIDs[0]])
            #expect(exprType == sema.types.booleanType)
        }
    }

    /// The compiler should not lower nullable-receiver isNullOrBlank() to the legacy
    /// String runtime helper after migration to bundled Kotlin source.
    @Test func testIsNullOrBlankDoesNotLowerToLegacyRuntimeHelper() throws {
        let source = """
        fun main() {
            val maybe: String? = null
            maybe.isNullOrBlank()
            val present: String? = "  "
            present.isNullOrBlank()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_string_isNullOrBlank"] == nil)
            #expect(throwFlags["kk_string_isNullOrBlank_flat"] == nil)
            #expect(throwFlags["__string_isNullOrBlank_flat"] == nil)
        }
    }
}
