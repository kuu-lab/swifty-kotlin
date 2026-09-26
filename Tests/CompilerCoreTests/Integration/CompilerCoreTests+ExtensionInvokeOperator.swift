#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// `operator fun invoke` declared as an EXTENSION (not a class/object member)
// used to be invisible to callable-value call syntax (`value(args)`):
// the invoke fallback in CallTypeChecker only walked the callee type's
// nominal member/supertype surface, which extension functions never join.
extension CompilerCoreTests {

    @Test func testExtensionInvokeOperatorResolvesForCallSyntax() throws {
        let sources: [String] = [
            // testExtensionInvokeOperatorResolvesForStringReceiver
            """
            package sample0
                    operator fun String.invoke(n: Int): String = repeat(n)
                    fun use(): String = "xy"(2)

            """,

            // testExtensionInvokeOperatorResolvesForUserClassReceiver
            """
            package sample1
                    class Box(val v: Int)
                    operator fun Box.invoke(k: Int): Int = v * k
                    fun use(): Int = Box(5)(2)

            """,

            // testNonOperatorExtensionInvokeDoesNotResolveCallSyntax
            """
            package sample2
                    fun String.invoke(n: Int): String = repeat(n)
                    fun use(): String {
                        val s = "xy"
                        return s(2)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testExtensionInvokeOperatorResolvesForStringReceiver
            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)
            }
            // testExtensionInvokeOperatorResolvesForUserClassReceiver
            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)
            }
            // testNonOperatorExtensionInvokeDoesNotResolveCallSyntax
            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)
            }
        }
    }
}
#endif
