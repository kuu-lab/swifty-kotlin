#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct InlineLambdaDefiniteAssignmentTests {
    @Test
    func testOnlyUnconditionalSingleInvocationInitializesCapturedVariable() throws {
        let sources = [
            """
            package inlineOnceExpression
            inline fun runIt(block: () -> Int): Int = block()
            fun g(block: () -> Int): Int {
                var result: Int
                runIt { result = block(); result }
                return result
            }
            """,
            """
            package inlineOnceBlock
            inline fun runIt(block: () -> Unit) { block() }
            fun g(): Int {
                var result: Int
                runIt { result = 42 }
                return result
            }
            """,
            """
            package inlineNever
            inline fun skip(block: () -> Unit) {}
            fun g(): Int {
                var result: Int
                skip { result = 42 }
                return result
            }
            """,
            """
            package inlineMaybe
            inline fun sometimes(flag: Boolean, block: () -> Unit) {
                if (flag) block()
            }
            fun g(): Int {
                var result: Int
                sometimes(false) { result = 42 }
                return result
            }
            """,
            """
            package ordinaryOnce
            fun runIt(block: () -> Unit) { block() }
            fun g(): Int {
                var result: Int
                runIt { result = 42 }
                return result
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(2) {
                assertNoDiagnostic("KSWIFTK-SEMA-0031", in: diagnosticsForPath(path, in: ctx))
            }
            for path in paths.dropFirst(2) {
                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }
}
#endif
