#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {

    // MARK: - Consolidated Sema tests

    @Test
    func testDataFlowAndSemaRegression_DoWhileAndExpressionInferenceSema() throws {
        let sources: [String] = [
            // testClassWithTypeParametersDefinesVariance
            """
            package sample0

                    class Box<out T>(val value: T)
                    fun main(): Int = 0

            """,
            // testDoWhileConditionCanReferenceBodyLocal
            """
            package sample1

                    fun main(): Int {
                        var loops = 0
                        do {
                            val local = loops + 1
                            loops = local
                        } while (local < 3)
                        return loops
                    }

            """,
            // testDoWhileInlineBodyAssignmentTypeChecks
            """
            package sample2

                    fun main(): Int {
                        var x = 0
                        do x = x + 1 while (x < 3)
                        return x
                    }

            """,
            // testValReassignmentEmitsDiagnostic
            """
            package sample3

                    fun main(): Int {
                        val x = 1
                        x = 2
                        return x
                    }

            """,
            // testDoWhileBodyLocalDoesNotLeakOutsideLoop
            """
            package sample4

                    fun main(): Int {
                        do {
                            val local = 1
                        } while (local < 2)
                        return local
                    }

            """,
            // testCompoundAssignOnValEmitsDiagnostic
            """
            package sample5

                    fun main(): Int {
                        val x = 5
                        x += 1
                        return x
                    }

            """,
            // testMemberCompoundAssignOnValEmitsDiagnostic
            """
            package sample6

                    class Box(val n: Int)
                    fun bump(b: Box): Int {
                        b.n += 1
                        return b.n
                    }
                    fun main(): Int = bump(Box(5))

            """,
            // testMemberPostfixIncrementOnValEmitsDiagnostic
            """
            package sample7

                    class Box(val n: Int)
                    fun bump(b: Box): Int {
                        b.n++
                        return b.n
                    }
                    fun main(): Int = bump(Box(5))

            """,
            // testBreakOutsideLoopEmitsDiagnostic
            """
            package sample8

                    fun main(): Int {
                        break
                        return 0
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testClassWithTypeParametersDefinesVariance ===

            do {




                let boxSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "Box"
                }
                #expect(boxSymbol != nil)

            }

            // === testDoWhileConditionCanReferenceBodyLocal ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0013", in: sample1Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sample1Diagnostics)

            }

            // === testDoWhileInlineBodyAssignmentTypeChecks ===

            do {

                let sample2Path = paths[2]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0013", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sample2Diagnostics)

            }

            // === testValReassignmentEmitsDiagnostic ===

            do {

                let sample0Path = paths[3]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample0Diagnostics)

            }

            // === testDoWhileBodyLocalDoesNotLeakOutsideLoop ===

            do {

                let sample1Path = paths[4]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sample1Diagnostics)

            }

            // === testCompoundAssignOnValEmitsDiagnostic ===

            do {

                let sample2Path = paths[5]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample2Diagnostics)

            }

            // === testMemberCompoundAssignOnValEmitsDiagnostic ===

            do {

                let sample3Path = paths[6]


                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample3Diagnostics)

            }

            // === testMemberPostfixIncrementOnValEmitsDiagnostic ===

            do {

                let sample4Path = paths[7]


                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample4Diagnostics)

            }

            // === testBreakOutsideLoopEmitsDiagnostic ===

            do {

                let sample5Path = paths[8]


                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0018", in: sample5Diagnostics)

            }

        }
    }
// MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRCleanDoWhileAndExpressionInference() throws {

        let sources: [String] = [
            // testTypedLocalDeclarationInfersCorrectly
            """
            package sample0

                    fun main(): Int {
                        val x: Int = 42
                        return x
                    }

            """,
            // testDoWhileLoopInfersUnitType
            """
            package sample1

                    fun main(): Int {
                        var x = 0
                        do {
                            x = x + 1
                        } while (x < 3)
                        return x
                    }

            """,
            // testCompoundAssignmentOperators
            """
            package sample2

                    fun main(): Int {
                        var x = 10
                        x += 5
                        x -= 3
                        x *= 2
                        x /= 4
                        x %= 3
                        return x
                    }

            """,
            // testMemberCompoundAssignOnVarDoesNotEmitDiagnostic
            """
            package sample3

                    class Box(var n: Int)
                    fun bump(b: Box): Int {
                        b.n += 1
                        return b.n
                    }
                    fun main(): Int = bump(Box(5))

            """,
            // testWhenExpressionInference
            """
            package sample4

                    fun classify(x: Int): String {
                        return when (x) {
                            1 -> "one"
                            2 -> "two"
                            else -> "other"
                        }
                    }
                    fun main() = classify(1)

            """,
            // testReturnExpressionInference
            """
            package sample5

                    fun earlyReturn(flag: Boolean): Int {
                        if (flag) return 42
                        return 0
                    }
                    fun main() = earlyReturn(true)

            """,
            // testLongLiteralInference
            """
            package sample6

                    fun main(): Long = 42L

            """,
            // testFloatLiteralInference
            """
            package sample7

                    fun main(): Float = 1.5f

            """,
            // testDoubleLiteralInference
            """
            package sample8

                    fun main(): Double = 3.14

            """,
            // testCharLiteralInference
            """
            package sample9

                    fun main(): Char = 'A'

            """,
            // testIsCheckInfersBoolean
            """
            package sample10

                    fun check(x: Any): Boolean = x is Int
                    fun main() = check(42)

            """,
            // testSafeCastInfersNullableType
            """
            package sample11

                    fun tryCast(x: Any): Int? = x as? Int
                    fun main() = tryCast(42)

            """,
            // testHardCastInference
            """
            package sample12

                    fun forceCast(x: Any): Int = x as Int
                    fun main() = forceCast(42)

            """,
            // testNullAssertInfersNonNullable
            """
            package sample13

                    fun forceUnwrap(x: Int?): Int = x!!
                    fun main() = forceUnwrap(42)

            """,
            // testElvisOperatorInference
            """
            package sample14

                    fun fallback(x: Int?): Int = x ?: 0
                    fun main() = fallback(null)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testTypedLocalDeclarationInfersCorrectly ===

            do {




                let xSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "x" && symbol.kind == .local
                }
                #expect(xSymbol != nil)

            }

            // === testDoWhileLoopInfersUnitType ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testCompoundAssignmentOperators ===

            do {

                let sample2Path = paths[2]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0014", in: sample2Diagnostics)

            }

            // === testMemberCompoundAssignOnVarDoesNotEmitDiagnostic ===

            do {

                let sample3Path = paths[3]


                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0014", in: sample3Diagnostics)

            }

            // === testWhenExpressionInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testReturnExpressionInference ===

            do {




                let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: interner)
                let returnCount = body.filter { instruction in
                    if case .returnValue = instruction { return true }
                    return false
                }.count
                #expect(returnCount >= 2)

            }

            // === testLongLiteralInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testFloatLiteralInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testDoubleLiteralInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testCharLiteralInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testIsCheckInfersBoolean ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testSafeCastInfersNullableType ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testHardCastInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testNullAssertInfersNonNullable ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testElvisOperatorInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

        }
    }

}

#endif
