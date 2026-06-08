@testable import CompilerCore
import Foundation
import XCTest

final class BigIntegerSyntheticLinkTests: XCTestCase {
    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - Helpers

    private func assertBigIntegerExtensionCalls(
        callName: String,
        source: String,
        expectedCount: Int,
        expectedLinkName: String,
        expectedFQName: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let calls = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == callName
            }

            XCTAssertEqual(calls.count, expectedCount,
                "Expected \(expectedCount) BigInteger.\(callName) calls",
                file: file, line: line)

            for callExpr in calls {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected BigInteger.\(callName) to resolve",
                    file: file, line: line
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLinkName,
                    file: file, line: line
                )
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
                let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
                XCTAssertEqual(fqName, expectedFQName, file: file, line: line)
            }
        }
    }

    // MARK: - and (existing, baseline)

    func testBigIntegerAndResolvesToSyntheticKotlinExtension() throws {
        let source = """
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val b = BigInteger("10")
            a and b
            a.and(b)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let andCalls = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "and"
            }

            XCTAssertEqual(andCalls.count, 2, "Expected both infix and dotted BigInteger.and calls")

            for callExpr in andCalls {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected BigInteger.and to resolve"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_biginteger_and"
                )

                let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
                let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
                XCTAssertEqual(fqName, ["kotlin", "and"])
            }
        }
    }

    // MARK: - Bitwise and shift extension functions (STDLIB-GAP-PH1)

    func testBigIntegerOrResolvesToSyntheticKotlinExtension() throws {
        try assertBigIntegerExtensionCalls(
            callName: "or",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12"); val b = BigInteger("10")
                a or b
                a.or(b)
            }
            """,
            expectedCount: 2,
            expectedLinkName: "kk_biginteger_or",
            expectedFQName: ["kotlin", "or"]
        )
    }

    func testBigIntegerXorResolvesToSyntheticKotlinExtension() throws {
        try assertBigIntegerExtensionCalls(
            callName: "xor",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12"); val b = BigInteger("10")
                a xor b
                a.xor(b)
            }
            """,
            expectedCount: 2,
            expectedLinkName: "kk_biginteger_xor",
            expectedFQName: ["kotlin", "xor"]
        )
    }

    func testBigIntegerInvResolvesToSyntheticKotlinExtension() throws {
        try assertBigIntegerExtensionCalls(
            callName: "inv",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12")
                a.inv()
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_not",
            expectedFQName: ["kotlin", "inv"]
        )
    }

    func testBigIntegerShlResolvesToSyntheticKotlinExtension() throws {
        try assertBigIntegerExtensionCalls(
            callName: "shl",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12")
                a shl 2
                a.shl(2)
            }
            """,
            expectedCount: 2,
            expectedLinkName: "kk_biginteger_shiftLeft",
            expectedFQName: ["kotlin", "shl"]
        )
    }

    func testBigIntegerShrResolvesToSyntheticKotlinExtension() throws {
        try assertBigIntegerExtensionCalls(
            callName: "shr",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12")
                a shr 2
                a.shr(2)
            }
            """,
            expectedCount: 2,
            expectedLinkName: "kk_biginteger_shiftRight",
            expectedFQName: ["kotlin", "shr"]
        )
    }

    // MARK: - Instance methods (STDLIB-GAP-PH1)

    func testBigIntegerToByteArrayResolvesToSyntheticInstanceMethod() throws {
        try assertBigIntegerExtensionCalls(
            callName: "toByteArray",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("255")
                a.toByteArray()
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_toByteArray",
            expectedFQName: ["java", "math", "BigInteger", "toByteArray"]
        )
    }

    func testBigIntegerModInverseResolvesToSyntheticInstanceMethod() throws {
        try assertBigIntegerExtensionCalls(
            callName: "modInverse",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("3"); val m = BigInteger("11")
                a.modInverse(m)
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_modInverse",
            expectedFQName: ["java", "math", "BigInteger", "modInverse"]
        )
    }

    func testBigIntegerModPowResolvesToSyntheticInstanceMethod() throws {
        try assertBigIntegerExtensionCalls(
            callName: "modPow",
            source: """
            import java.math.BigInteger
            fun main() {
                val base = BigInteger("2")
                val exp = BigInteger("10")
                val mod = BigInteger("1000")
                base.modPow(exp, mod)
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_modPow",
            expectedFQName: ["java", "math", "BigInteger", "modPow"]
        )
    }
}
