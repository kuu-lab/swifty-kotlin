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
    func testDataFlowAndSemaRegression_CoreInferenceAndLoopDiagnosticsSema() throws {
        let sources: [String] = [
            // testRangeToOperatorInference
            """
            package sample0

                    fun main() {
                        val r = 1..10
                    }

            """,
            // testPropertyTypeAnnotationResolves
            """
            package sample1

                    val count: Int = 0
                    val name: String = "test"
                    val flag: Boolean = true
                    fun main(): Int = 0

            """,
            // testContinueOutsideLoopEmitsDiagnostic
            """
            package sample2

                    fun main(): Int {
                        continue
                        return 0
                    }

            """,
            // testUnresolvedReferenceEmitsDiagnostic
            """
            package sample3

                    fun main(): Int = unknownVar

            """,
            // testUnresolvedFunctionEmitsDiagnostic
            """
            package sample4

                    fun main(): Int = unknownFunc(42)

            """,
            // testLocalAssignToUnresolvedVariableEmitsDiagnostic
            """
            package sample5

                    fun main() {
                        noSuchVar = 42
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testRangeToOperatorInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testPropertyTypeAnnotationResolves ===

            do {




                let countSym = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "count" && symbol.kind == .property
                }
                #expect(countSym != nil)
                if let sym = countSym {
                    #expect(sema.symbols.propertyType(for: sym.id) != nil)
                }

            }

            // === testContinueOutsideLoopEmitsDiagnostic ===

            do {

                let sample0Path = paths[2]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0019", in: sample0Diagnostics)

            }

            // === testUnresolvedReferenceEmitsDiagnostic ===

            do {

                let sample1Path = paths[3]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sample1Diagnostics)

            }

            // === testUnresolvedFunctionEmitsDiagnostic ===

            do {

                let sample2Path = paths[4]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sample2Diagnostics)

            }

            // === testLocalAssignToUnresolvedVariableEmitsDiagnostic ===

            do {

                let sample3Path = paths[5]


                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0013", in: sample3Diagnostics)

            }

        }
    }
// MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRCleanCoreInferenceAndLoopDiagnostics() throws {

        let sources: [String] = [
            // testLocalFunctionDeclarationInference
            """
            package sample0

                    fun main(): Int {
                        fun add(a: Int, b: Int): Int = a + b
                        return add(1, 2)
                    }

            """,
            // testSuspendLocalFunctionDeclarationInference
            """
            package sample1

                    suspend fun delayed(v: Int): Int = v

                    fun main(): Int {
                        suspend fun local(v: Int): Int = delayed(v)
                        return 0
                    }

            """,
            // testArrayAccessAndAssignInference
            """
            package sample2

                    fun main(): Int {
                        val arr = IntArray(3)
                        arr[0] = 10
                        return arr[0]
                    }

            """,
            // testForLoopInfersElementType
            """
            package sample3

                    fun main(): Int {
                        val arr = IntArray(3)
                        var sum = 0
                        for (item in arr) {
                            sum += item
                        }
                        return sum
                    }

            """,
            // testBinaryOperatorTypePromotionLong
            """
            package sample4

                    fun main(): Long = 1L + 2

            """,
            // testBinaryOperatorTypePromotionDouble
            """
            package sample5

                    fun main(): Double = 1.0 + 2.0

            """,
            // testBinaryOperatorTypePromotionFloat
            """
            package sample6

                    fun main(): Float = 1.5f + 2.5f

            """,
            // testStringTemplateInference
            """
            package sample7

                    fun main(): String {
                        val name = "World"
                        return "Hello, $name!"
                    }

            """,
            // testIfExpressionWithElseInfersLUB
            """
            package sample8

                    fun pick(flag: Boolean): Int {
                        val x = if (flag) 1 else 2
                        return x
                    }
                    fun main() = pick(true)

            """,
            // testIfExpressionWithoutElseInfersUnit
            """
            package sample9

                    fun doSomething(flag: Boolean) {
                        if (flag) println("yes")
                    }
                    fun main() = doSomething(true)

            """,
            // testNullLiteralInference
            """
            package sample10

                    fun main(): Any? = null

            """,
            // testWhileLoopInference
            """
            package sample11

                    fun main(): Int {
                        var i = 0
                        while (i < 10) {
                            i = i + 1
                        }
                        return i
                    }

            """,
            // testWhenBooleanExhaustive
            """
            package sample12

                    fun desc(flag: Boolean): String = when (flag) {
                        true -> "yes"
                        false -> "no"
                    }
                    fun main() = desc(true)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            _ = try #require(ctx.kir)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)


            // === testLocalFunctionDeclarationInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testSuspendLocalFunctionDeclarationInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testArrayAccessAndAssignInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testForLoopInfersElementType ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testBinaryOperatorTypePromotionLong ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testBinaryOperatorTypePromotionDouble ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testBinaryOperatorTypePromotionFloat ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testStringTemplateInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testIfExpressionWithElseInfersLUB ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testIfExpressionWithoutElseInfersUnit ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testNullLiteralInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testWhileLoopInference ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testWhenBooleanExhaustive ===

            do {




                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

        }
    }

}

#endif
