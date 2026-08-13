@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-019/063/112/031/032: misc String/CharSequence helpers.
///
/// `indent(n)`, `reversed()`, `trimIndent()`, `isNullOrEmpty()`, and `isNullOrBlank()`
/// are wired through bundled Kotlin source. These tests verify Sema resolution,
/// return typing, argument validation, and KIR lowering (for nullable predicate
/// helpers) without routing to legacy `kk_string_*` runtime helpers.
@Suite
struct StringMiscFunctionTests {
    private static let cleanSources: [String] = [
        """
        package sample0

        fun main() {
            val noArg: String = "hello".indent()
            val withInt: String = "hello".indent(2)
            val negative: String = "  hello".indent(-2)
            val returnIsString: Int = "  hello".indent(2).length
            val chained: String = "  abc".indent(2).trim()
        }
        """,
        """
        package sample1

        fun main() {
            val literal: String = "hello".reversed()
            val source: String = "kotlin"
            val flipped: String = source.reversed()
            val n: Int = "abcde".reversed().length
            val chained: String = "abc".reversed().reversed()
        }
        """,
        """
        package sample2

        fun main() {
            val literal: String = "    hello".trimIndent()
            val source: String = "  line"
            val dedented: String = source.trimIndent()
            val returnIsString: Int = "    abcde".trimIndent().length
            val chained: String = "  abc".trimIndent().trim()
        }
        """,
        """
        package sample3

        fun classifyNullable(value: String?): Boolean {
            return value.isNullOrEmpty()
        }

        fun classifyNonNull(value: String): Boolean {
            return value.isNullOrEmpty()
        }
        """,
        """
        package sample4

        fun classifyNullable(value: String?): Boolean {
            return value.isNullOrBlank()
        }

        fun classifyNonNull(value: String): Boolean {
            return value.isNullOrBlank()
        }
        """,
    ]

    private static let errorSources: [String] = [
        """
        package sample0_error

        fun main() {
            val s = "hello".indent("  ")
        }
        """,
        """
        package sample1_error

        fun main() {
            val s = "abc".reversed(1)
        }
        """,
        """
        package sample2_error

        fun main() {
            val s = "abc".trimIndent(1)
        }
        """,
        """
        package sample3_error

        fun classify(): Boolean {
            return null.isNullOrEmpty()
        }
        """,
    ]

    private static let loweringSource: String = """
    package sample5

    fun main() {
        val maybe: String? = null
        maybe.isNullOrEmpty()
        maybe.isNullOrBlank()
        val present: String? = ""
        present.isNullOrEmpty()
        present.isNullOrBlank()
    }
    """

    @Test func testSemaResolvesCleanly() throws {
        try withTemporaryFiles(contents: Self.cleanSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected clean sources to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let isNullOrEmptyIDs = allMemberCallExprIDs(
                named: "isNullOrEmpty",
                in: ast,
                interner: ctx.interner
            )
            #expect(
                isNullOrEmptyIDs.count == 2,
                "Expected calls for nullable and non-null isNullOrEmpty receivers"
            )
            for callID in isNullOrEmptyIDs {
                let exprType = try #require(sema.bindings.exprTypes[callID])
                #expect(
                    exprType == sema.types.booleanType,
                    "isNullOrEmpty should be typed as Boolean"
                )
            }

            let isNullOrBlankIDs = allMemberCallExprIDs(
                named: "isNullOrBlank",
                in: ast,
                interner: ctx.interner
            )
            #expect(
                isNullOrBlankIDs.count == 2,
                "Expected calls for nullable and non-null isNullOrBlank receivers"
            )
            for callID in isNullOrBlankIDs {
                let exprType = try #require(sema.bindings.exprTypes[callID])
                #expect(
                    exprType == sema.types.booleanType,
                    "isNullOrBlank should be typed as Boolean"
                )
            }
        }
    }

    @Test func testSemaRejectsInvalidCalls() throws {
        try withTemporaryFiles(contents: Self.errorSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(
                ctx.diagnostics.hasError,
                "Expected invalid calls to produce diagnostics, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test func testNullablePredicatesDoNotLowerToLegacyRuntimeHelpers() throws {
        try withTemporaryFile(contents: Self.loweringSource) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_string_isNullOrEmpty"] == nil)
            #expect(throwFlags["kk_string_isNullOrEmpty_flat"] == nil)
            #expect(throwFlags["__string_isNullOrEmpty_flat"] == nil)
            #expect(throwFlags["kk_string_isNullOrBlank"] == nil)
            #expect(throwFlags["kk_string_isNullOrBlank_flat"] == nil)
            #expect(throwFlags["__string_isNullOrBlank_flat"] == nil)
        }
    }

    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { return nil }
            return exprID
        }
    }
}
