@testable import CompilerCore
import Foundation
import Testing

/// Verifies `String?.toBoolean()` (STDLIB-TEXT-FN-087) resolves cleanly in Sema
/// for both nullable and non-null receivers and lowers through to the runtime
/// helper `kk_string_toBoolean`, which is classified as non-throwing per
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

    /// Sema should accept `String?.toBoolean()` directly (no safe-call needed)
    /// because the Kotlin signature is `fun String?.toBoolean(): Boolean`.
    @Test func testToBooleanOnNullableStringResolvesToNonNullBoolean() throws {
        let source = """
        fun parse(value: String?): Boolean {
            return value.toBoolean()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected toBoolean on String? to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "toBoolean", in: ast, interner: ctx.interner)
            #expect(callIDs.count == 1)
            let exprType = try #require(sema.bindings.exprTypes[callIDs[0]])
            #expect(
                exprType == sema.types.booleanType,
                "toBoolean should be typed as Boolean even for nullable receivers"
            )
        }
    }

    /// Receiver typed as non-null `String` should also resolve to `Boolean`.
    @Test func testToBooleanOnNonNullStringResolves() throws {
        let source = """
        fun parse(value: String): Boolean {
            return value.toBoolean()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected toBoolean on String to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "toBoolean", in: ast, interner: ctx.interner)
            #expect(callIDs.count == 1)
            let exprType = try #require(sema.bindings.exprTypes[callIDs[0]])
            #expect(exprType == sema.types.booleanType)
        }
    }

    /// `toBoolean()` should lower to `kk_string_toBoolean` and be classified as
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

    /// STDLIB-TEXT-FN-089: `String.toBooleanStrictOrNull()` returns a *nullable*
    /// `Boolean` — the strict parser yields `null` instead of throwing when the
    /// text is neither "true" nor "false". This distinguishes it from
    /// `toBoolean`/`toBooleanStrict`, which both resolve to a non-null `Boolean`.
    @Test func testToBooleanStrictOrNullResolvesToNullableBoolean() throws {
        let source = """
        fun parse(value: String): Boolean? {
            return value.toBooleanStrictOrNull()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected toBooleanStrictOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "toBooleanStrictOrNull", in: ast, interner: ctx.interner)
            #expect(callIDs.count == 1)
            let exprType = try #require(sema.bindings.exprTypes[callIDs[0]])
            #expect(
                exprType == sema.types.make(.primitive(.boolean, .nullable)),
                "toBooleanStrictOrNull should be typed as nullable Boolean (Boolean?)"
            )
        }
    }

    /// `toBooleanStrictOrNull()` should lower to `kk_string_toBooleanStrictOrNull`
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
                throwFlags["kk_string_toBooleanStrictOrNull"],
                "Expected kk_string_toBooleanStrictOrNull calls to appear in main()"
            )
            #expect(orNullFlags.count == 3)
            #expect(
                orNullFlags.allSatisfy { $0 == false },
                "kk_string_toBooleanStrictOrNull must be lowered as non-throwing"
            )
        }
    }
}
