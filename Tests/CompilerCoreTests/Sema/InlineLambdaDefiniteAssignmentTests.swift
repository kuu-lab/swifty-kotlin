#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct InlineLambdaDefiniteAssignmentTests {
    @Test
    func testParameterizedInlineContractInitializesCapturedVariable() throws {
        let kinds = ["EXACTLY_ONCE", "AT_LEAST_ONCE", "AT_MOST_ONCE", "UNKNOWN", ""]
        let sources = kinds.enumerated().map { index, kind in
            """
            package parameterizedContract\(index)
            import kotlin.contracts.*
            @OptIn(ExperimentalContracts::class)
            inline fun readFromHead(head: Int, block: (Int) -> Int): Int {
                contract { callsInPlace(block\(kind.isEmpty ? "" : ", InvocationKind.\(kind)")) }
                return block(head)
            }
            fun read(block: (Int) -> Int): Int {
                var result: Int
                readFromHead(block = { array ->
                    result = block(array)
                    result
                }, head = 0)
                return result
            }
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(2) {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
            for path in paths.dropFirst(2) {
                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }

    @Test
    func testParameterizedInlineCallRequiresGuaranteedAssignment() throws {
        let sources = [
            """
            package parameterizedNoContract
            inline fun readFromHead(block: (Int) -> Int): Int = block(0)
            fun read(block: (Int) -> Int): Int {
                var result: Int
                readFromHead { array -> result = block(array); result }
                return result
            }
            """,
            """
            package parameterizedConditionalAssignment
            import kotlin.contracts.*
            @OptIn(ExperimentalContracts::class)
            inline fun readFromHead(block: (Int) -> Int): Int {
                contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
                return block(0)
            }
            fun read(flag: Boolean): Int {
                var result: Int
                readFromHead { array ->
                    if (flag) result = array
                    array
                }
                return result
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }

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
