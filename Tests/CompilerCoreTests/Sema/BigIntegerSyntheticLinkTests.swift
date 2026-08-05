@testable import CompilerCore
import Testing

@Suite
struct BigIntegerSyntheticLinkTests {
    /// Collect user expressions while skipping bundled stdlib files so that
    /// bitwise ops inside Random.nextLong / nextDouble don't pollute counts.
    /// When `path` is supplied, restrict to expressions from that source file.
    private func userExprIDs(
        in ast: ASTModule,
        sourceManager: SourceManager,
        path: String? = nil,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else { return nil }
            if let range = ast.arena.exprRange(exprID),
               sourceManager.path(of: range.start.file).starts(with: "__bundled_") {
                return nil
            }
            if let path = path,
               let range = ast.arena.exprRange(exprID),
               sourceManager.path(of: range.start.file) != path {
                return nil
            }
            return exprID
        }
    }

    @Test
    func testBigIntegerSyntheticLinks() throws {
        let testCases: [(source: String, callName: String, expectedCount: Int, expectedLinkName: String, expectedFQName: [String])] = [
            (
                """
                package sample0

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    val b = BigInteger("10")
                    a and b
                    a.and(b)
                }
                """,
                "and",
                2,
                "kk_biginteger_and",
                ["kotlin", "and"]
            ),
            (
                """
                package sample1

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12"); val b = BigInteger("10")
                    a or b
                    a.or(b)
                }
                """,
                "or",
                2,
                "kk_biginteger_or",
                ["kotlin", "or"]
            ),
            (
                """
                package sample2

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12"); val b = BigInteger("10")
                    a xor b
                    a.xor(b)
                }
                """,
                "xor",
                2,
                "kk_biginteger_xor",
                ["kotlin", "xor"]
            ),
            (
                """
                package sample3

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    a.inv()
                }
                """,
                "inv",
                1,
                "kk_biginteger_not",
                ["kotlin", "inv"]
            ),
            (
                """
                package sample4

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    a shl 2
                    a.shl(2)
                }
                """,
                "shl",
                2,
                "kk_biginteger_shiftLeft",
                ["kotlin", "shl"]
            ),
            (
                """
                package sample5

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    a shr 2
                    a.shr(2)
                }
                """,
                "shr",
                2,
                "kk_biginteger_shiftRight",
                ["kotlin", "shr"]
            ),
            (
                """
                package sample6

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("255")
                    a.toByteArray()
                }
                """,
                "toByteArray",
                1,
                "kk_biginteger_toByteArray",
                ["java", "math", "BigInteger", "toByteArray"]
            ),
            (
                """
                package sample7

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("3"); val m = BigInteger("11")
                    a.modInverse(m)
                }
                """,
                "modInverse",
                1,
                "kk_biginteger_modInverse",
                ["java", "math", "BigInteger", "modInverse"]
            ),
            (
                """
                package sample8

                import java.math.BigInteger

                fun main() {
                    val base = BigInteger("2")
                    val exp = BigInteger("10")
                    val mod = BigInteger("1000")
                    base.modPow(exp, mod)
                }
                """,
                "modPow",
                1,
                "kk_biginteger_modPow",
                ["java", "math", "BigInteger", "modPow"]
            ),
            (
                """
                package sample9

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    a.not()
                }
                """,
                "not",
                1,
                "kk_biginteger_not",
                ["java", "math", "BigInteger", "not"]
            ),
            (
                """
                package sample10

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    a.shiftLeft(3)
                }
                """,
                "shiftLeft",
                1,
                "kk_biginteger_shiftLeft",
                ["java", "math", "BigInteger", "shiftLeft"]
            ),
            (
                """
                package sample11

                import java.math.BigInteger

                fun main() {
                    val a = BigInteger("12")
                    a.shiftRight(2)
                }
                """,
                "shiftRight",
                1,
                "kk_biginteger_shiftRight",
                ["java", "math", "BigInteger", "shiftRight"]
            ),
        ]

        let sources = testCases.map { $0.source }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected BigInteger synthetic member sources to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for (index, testCase) in testCases.enumerated() {
                let samplePath = paths[index]
                let calls = userExprIDs(
                    in: ast,
                    sourceManager: ctx.sourceManager,
                    path: samplePath
                ) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == testCase.callName
                }

                #expect(
                    calls.count == testCase.expectedCount,
                    "Expected \(testCase.expectedCount) BigInteger.\(testCase.callName) calls in \(samplePath), got \(calls.count)"
                )

                for callExpr in calls {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected a chosen callee for BigInteger.\(testCase.callName)"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == testCase.expectedLinkName,
                        "Expected BigInteger.\(testCase.callName) to link to \(testCase.expectedLinkName)"
                    )
                    let symbol = try #require(sema.symbols.symbol(chosenCallee))
                    let fqName = symbol.fqName.map { ctx.interner.resolve($0) }
                    #expect(
                        fqName == testCase.expectedFQName,
                        "Expected BigInteger.\(testCase.callName) fqName to be \(testCase.expectedFQName), got \(fqName)"
                    )
                }
            }
        }
    }
}
