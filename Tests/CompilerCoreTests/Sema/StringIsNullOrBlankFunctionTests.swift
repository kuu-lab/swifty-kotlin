@testable import CompilerCore
import Foundation
import Testing

/// Verifies CharSequence?.isNullOrBlank() (STDLIB-TEXT-FN-032) resolves cleanly
/// in Sema and lowers through the nullable-receiver fallback to the runtime
/// helper `kk_string_isNullOrBlank_flat`.
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

    /// The compiler should lower nullable-receiver isNullOrBlank() to the runtime helper
    /// `kk_string_isNullOrBlank_flat`, classified as non-throwing.
    @Test func testIsNullOrBlankLowersToRuntimeHelperNonThrowing() throws {
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
            let isNullOrBlankFlags = try #require(
                throwFlags["kk_string_isNullOrBlank_flat"],
                "Expected kk_string_isNullOrBlank_flat calls to appear in main()"
            )
            #expect(isNullOrBlankFlags.count == 2)
            #expect(isNullOrBlankFlags.allSatisfy { $0 == false })
        }
    }
}
