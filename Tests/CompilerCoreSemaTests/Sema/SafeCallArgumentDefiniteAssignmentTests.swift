#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-4625: `a?.f(<args>)` skips argument evaluation when `a` is null, so a
/// definite assignment performed inside the arguments must stay conditional.
@Suite
struct SafeCallArgumentDefiniteAssignmentTests {
    @Test
    func testAssignmentInsideSafeCallArgumentIsNotDefinite() throws {
        let sources = [
            """
            package blockArgument
            fun read(s: String?): Int {
                var x: Int
                s?.let(if (true) { x = 5; { _: String -> } } else { { _ -> } })
                return x
            }
            """,
            """
            package nestedContract
            fun read(s: String?): Int {
                var x: Int
                s?.takeIf(run { x = 5; { it.isEmpty() } })
                return x
            }
            """,
            """
            package definitelyNullReceiver
            fun read(): Int {
                var x: Int
                val s: String? = null
                s?.let(if (true) { x = 5; { _: String -> } } else { { _ -> } })
                return x
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
    func testAssignmentInsideSafeCallReceiverStaysDefinite() throws {
        let sources = [
            """
            package receiverAssignment
            fun read(s: String?): Int {
                var x: Int
                run { x = 5; s }?.let { _ -> }
                return x
            }
            """,
            """
            package plainCallArgument
            fun read(s: String): Int {
                var x: Int
                s.plus(run { x = 5; "a" })
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
        }
    }

    @Test
    func testElvisNothingFallbackKeepsArgumentAssignmentDefinite() throws {
        let sources = [
            """
            package elvisReturn
            fun read(s: String?): Int {
                var x: Int
                s?.plus(run { x = 5; "a" }) ?: return 0
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
        }
    }

    @Test
    func testValAssignedInSafeCallArgumentRejectsLaterReassignment() throws {
        let sources = [
            """
            package valReassign
            fun read(s: String?, b: Boolean): Int {
                val x: Int
                s?.plus(if (b) { x = 5; "a" } else { x = 6; "b" })
                x = 7
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }

    @Test
    func testElvisNothingFallbackAfterSafeCallChainKeepsEarlierArgumentAssignmentDefinite() throws {
        let sources = [
            """
            package elvisChain
            fun read(s: String?): Int {
                var x: Int
                s?.plus(run { x = 5; "a" })?.length ?: return 0
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
        }
    }

    @Test
    func testPossibleAssignmentSurvivesBlockAndBranchJoin() throws {
        let sources = [
            """
            package branchJoin
            fun read(s: String?, b: Boolean, c: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                } else {
                    x = 7
                }
                x = 8
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }

    @Test
    func testPossibleAssignmentFromBranchThatNeverCompletesIsDropped() throws {
        let sources = [
            """
            package nonCompletingBranch
            fun read(s: String?, b: Boolean, c: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                    try { println("work") } finally { return 0 }
                }
                x = 8
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
        }
    }

    @Test
    func testPossibleAssignmentSurvivesBranchWithLabeledReturnToInlineLambda() throws {
        let sources = [
            """
            package labeledReturnBranch
            fun read(s: String?, b: Boolean, c: Boolean, d: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                    run<Int> {
                        if (d) return@run 1
                        throw IllegalStateException()
                    }
                }
                x = 8
                return x
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }
}
#endif
