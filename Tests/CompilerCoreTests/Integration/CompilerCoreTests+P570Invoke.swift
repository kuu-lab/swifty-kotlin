#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {

    @Test func testP570Sema() throws {
        let sources: [String] = [
            // testInvokeOperatorResolvesForTopLevelPropertyCallee
            """
            package sample0
                    class Adder {
                        operator fun invoke(x: Int): Int = x + 1
                    }
                    val globalAdder: Adder = Adder()
                    fun use(): Int = globalAdder(41)

            """,

            // testInvokeOperatorResolvesForObjectSingletonCallee
            """
            package sample1
                    object Incrementer {
                        operator fun invoke(x: Int): Int = x + 1
                    }
                    fun use(): Int = Incrementer(41)

            """,

            // testInvokeOperatorResolvesForExpressionResultCallee
            """
            package sample2
                    class Adder {
                        operator fun invoke(x: Int): Int = x + 1
                    }
                    fun makeAdder(): Adder = Adder()
                    fun use(): Int = makeAdder()(41)

            """,

            // testNonOperatorInvokeDoesNotResolveCallSyntax
            """
            package sample3
                    class Adder {
                        fun invoke(x: Int): Int = x + 1
                    }
                    fun use(): Int {
                        val adder: Adder = Adder()
                        return adder(41)
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testInvokeOperatorResolvesForTopLevelPropertyCallee

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testInvokeOperatorResolvesForObjectSingletonCallee

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testInvokeOperatorResolvesForExpressionResultCallee

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testNonOperatorInvokeDoesNotResolveCallSyntax

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }

        }
    }

}
#endif
