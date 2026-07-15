#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct BigIntegerSyntheticLinkTests {
    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    // Like allExprIDs but skips expressions from bundled stdlib files so that
    // bitwise ops inside Random.nextLong / nextDouble don't pollute counts.
    private func userExprIDs(
        in ast: ASTModule,
        sourceManager: SourceManager,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else { return nil }
            if let range = ast.arena.exprRange(exprID),
               sourceManager.path(of: range.start.file).starts(with: "__bundled_") {
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = userExprIDs(in: ast, sourceManager: ctx.sourceManager) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == callName
            }

            #expect(calls.count == expectedCount, "Expected \(expectedCount) BigInteger.\(callName) calls")

            for callExpr in calls {
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedLinkName)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
                #expect(fqName == expectedFQName)
            }
        }
    }

    // MARK: - and (existing, baseline)

    @Test
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let andCalls = userExprIDs(in: ast, sourceManager: ctx.sourceManager) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "and"
            }

            #expect(andCalls.count == 2, "Expected both infix and dotted BigInteger.and calls")

            for callExpr in andCalls {
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_biginteger_and")

                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
                #expect(fqName == ["kotlin", "and"])
            }
        }
    }

    // MARK: - Bitwise and shift extension functions (STDLIB-GAP-PH1)

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    // MARK: - Raw Java instance methods (STDLIB-NUM-129 follow-up: not/shiftLeft/shiftRight)

    @Test
    func testBigIntegerNotResolvesToSyntheticInstanceMethod() throws {
        try assertBigIntegerExtensionCalls(
            callName: "not",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12")
                a.not()
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_not",
            expectedFQName: ["java", "math", "BigInteger", "not"]
        )
    }

    @Test
    func testBigIntegerShiftLeftResolvesToSyntheticInstanceMethod() throws {
        try assertBigIntegerExtensionCalls(
            callName: "shiftLeft",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12")
                a.shiftLeft(3)
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_shiftLeft",
            expectedFQName: ["java", "math", "BigInteger", "shiftLeft"]
        )
    }

    @Test
    func testBigIntegerShiftRightResolvesToSyntheticInstanceMethod() throws {
        try assertBigIntegerExtensionCalls(
            callName: "shiftRight",
            source: """
            import java.math.BigInteger
            fun main() {
                val a = BigInteger("12")
                a.shiftRight(2)
            }
            """,
            expectedCount: 1,
            expectedLinkName: "kk_biginteger_shiftRight",
            expectedFQName: ["java", "math", "BigInteger", "shiftRight"]
        )
    }
}
#endif
