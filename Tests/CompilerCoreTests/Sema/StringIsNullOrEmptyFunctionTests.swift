@testable import CompilerCore
import Foundation
import XCTest

/// Verifies CharSequence?.isNullOrEmpty() (STDLIB-TEXT-FN-031) resolves cleanly
/// in Sema and lowers through the nullable-receiver fallback to the runtime
/// helper `kk_string_isNullOrEmpty`.
final class StringIsNullOrEmptyFunctionTests: XCTestCase {
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

    /// Sema should accept `String?.isNullOrEmpty()` and return Boolean.
    func testIsNullOrEmptyOnNullableStringResolvesToBoolean() throws {
        let source = """
        fun classify(value: String?): Boolean {
            return value.isNullOrEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected isNullOrEmpty to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "isNullOrEmpty", in: ast, interner: ctx.interner)
            XCTAssertEqual(callIDs.count, 1)
            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callIDs[0]])
            XCTAssertEqual(
                exprType,
                sema.types.booleanType,
                "isNullOrEmpty should be typed as Boolean"
            )
        }
    }

    /// Receiver typed as non-null String should still resolve isNullOrEmpty.
    func testIsNullOrEmptyOnNonNullStringResolves() throws {
        let source = """
        fun classify(value: String): Boolean {
            return value.isNullOrEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected isNullOrEmpty on non-null String to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "isNullOrEmpty", in: ast, interner: ctx.interner)
            XCTAssertEqual(callIDs.count, 1)
            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callIDs[0]])
            XCTAssertEqual(exprType, sema.types.booleanType)
        }
    }

    /// The compiler should lower nullable-receiver isNullOrEmpty() to the runtime helper
    /// `kk_string_isNullOrEmpty`, classified as non-throwing.
    func testIsNullOrEmptyLowersToRuntimeHelperNonThrowing() throws {
        let source = """
        fun main() {
            val maybe: String? = null
            maybe.isNullOrEmpty()
            val present: String? = ""
            present.isNullOrEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let isNullOrEmptyFlags = try XCTUnwrap(
                throwFlags["kk_string_isNullOrEmpty"],
                "Expected kk_string_isNullOrEmpty calls to appear in main()"
            )
            XCTAssertEqual(isNullOrEmptyFlags.count, 2)
            XCTAssertTrue(isNullOrEmptyFlags.allSatisfy { $0 == false })
        }
    }
}
