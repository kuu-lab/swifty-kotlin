@testable import CompilerCore
import Foundation
import Testing

/// Verifies `String?.toBoolean()` (STDLIB-TEXT-FN-087) resolves cleanly in Sema
/// for both nullable and non-null receivers and lowers through to the runtime
/// helper `kk_string_toBoolean_flat`, which is classified as non-throwing per
/// Kotlin's specification (`null.toBoolean()` returns `false`, never throws).
@Suite
struct StringToBooleanFunctionTests {
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

    @Test func testToBooleanResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parseNullable(value: String?): Boolean {
            return value.toBoolean()
        }

        fun parseNonNull(value: String): Boolean {
            return value.toBoolean()
        }

        fun parseStrictOrNull(value: String): Boolean? {
            return value.toBooleanStrictOrNull()
        }
        """)

        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected toBoolean/toBooleanStrictOrNull to resolve cleanly, got: \(diagnosticSummary)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let toBooleanCalls = allMemberCallExprIDs(named: "toBoolean", in: ast, interner: ctx.interner)
        #expect(toBooleanCalls.count == 2)
        for callID in toBooleanCalls {
            let exprType = try #require(sema.bindings.exprTypes[callID])
            #expect(
                exprType == sema.types.booleanType,
                "toBoolean should be typed as Boolean"
            )
        }

        let orNullCalls = allMemberCallExprIDs(named: "toBooleanStrictOrNull", in: ast, interner: ctx.interner)
        #expect(orNullCalls.count == 1)
        let orNullType = try #require(sema.bindings.exprTypes[orNullCalls[0]])
        #expect(
            orNullType == sema.types.make(.primitive(.boolean, .nullable)),
            "toBooleanStrictOrNull should be typed as nullable Boolean (Boolean?)"
        )
    }

    /// `toBoolean()` should lower to `kk_string_toBoolean_flat` and be classified as
    /// non-throwing — `null.toBoolean()` is defined to return `false`, so there
    /// is no NumberFormatException equivalent that propagates out.
    @Test func testToBooleanLowersToRuntimeHelperNonThrowing() throws {
        let source = """
        fun main() {
            val missing: String? = null
            missing.toBoolean()
            val present: String? = "TRUE"
            present.toBoolean()
            val concrete: String = "false"
            concrete.toBoolean()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let toBooleanFlags = try #require(
                throwFlags["kk_string_toBoolean"],
                "Expected kk_string_toBoolean calls to appear in main()"
            )
            #expect(toBooleanFlags.count == 3)
            #expect(
                toBooleanFlags.allSatisfy { $0 == false },
                "kk_string_toBoolean must be lowered as non-throwing"
            )
        }
    }

    /// `toBooleanStrictOrNull()` should lower to `kk_string_toBooleanStrictOrNull_flat`
    /// and be classified as non-throwing: unlike `toBooleanStrict`, the OrNull
    /// variant signals failure with a `null` sentinel rather than an exception, so
    /// no thrown-pointer plumbing is emitted at the call site.
    @Test func testToBooleanStrictOrNullLowersToRuntimeHelperNonThrowing() throws {
        let source = """
        fun main() {
            val yes: String = "true"
            yes.toBooleanStrictOrNull()
            val no: String = "false"
            no.toBooleanStrictOrNull()
            val other: String = "yes"
            other.toBooleanStrictOrNull()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let orNullFlags = try #require(
                throwFlags["kk_string_toBooleanStrictOrNull_flat"],
                "Expected kk_string_toBooleanStrictOrNull_flat calls to appear in main()"
            )
            #expect(orNullFlags.count == 3)
            #expect(
                orNullFlags.allSatisfy { $0 == false },
                "kk_string_toBooleanStrictOrNull_flat must be lowered as non-throwing"
            )
        }
    }
}
