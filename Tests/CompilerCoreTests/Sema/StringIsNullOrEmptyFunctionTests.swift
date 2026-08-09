@testable import CompilerCore
import Foundation
import Testing

/// Verifies CharSequence?.isNullOrEmpty() (STDLIB-TEXT-FN-031) resolves cleanly
/// in Sema through bundled Kotlin source.
@Suite
struct StringIsNullOrEmptyFunctionTests {
    @Test func testIsNullOrEmptyResolvesInSource() throws {
        let source = """
        fun classifyNullable(value: String?): Boolean {
            return value.isNullOrEmpty()
        }

        fun classifyNonNull(value: String): Boolean {
            return value.isNullOrEmpty()
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
                "Expected isNullOrEmpty to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let callIDs = isNullOrEmptyCallIDs(in: ast, interner: interner)
            #expect(callIDs.count == 2, "Expected calls for nullable and non-null receivers")
            for callID in callIDs {
                let exprType = try #require(sema.bindings.exprTypes[callID])
                #expect(
                    exprType == sema.types.booleanType,
                    "isNullOrEmpty should be typed as Boolean"
                )
            }
        }
    }

    /// A bare null receiver should stay ambiguous because Kotlin stdlib also
    /// exposes Array/Collection/Map nullable-receiver isNullOrEmpty overloads.
    @Test func testNullLiteralIsNullOrEmptyIsAmbiguous() throws {
        let source = """
        fun classify(): Boolean {
            return null.isNullOrEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.hasError)
            #expect(
                ctx.diagnostics.diagnostics.contains { diagnostic in
                    diagnostic.code == "KSWIFTK-SEMA-0003"
                },
                "Expected null.isNullOrEmpty() to match kotlinc ambiguity diagnostics"
            )
        }
    }

    /// The compiler should not lower nullable-receiver isNullOrEmpty() to the legacy
    /// String runtime helper after migration to bundled Kotlin source.
    @Test func testIsNullOrEmptyDoesNotLowerToLegacyRuntimeHelper() throws {
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

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_string_isNullOrEmpty"] == nil)
            #expect(throwFlags["kk_string_isNullOrEmpty_flat"] == nil)
            #expect(throwFlags["__string_isNullOrEmpty_flat"] == nil)
        }
    }

    private func isNullOrEmptyCallIDs(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == "isNullOrEmpty"
            else { continue }
            results.append(exprID)
        }
        return results
    }
}
