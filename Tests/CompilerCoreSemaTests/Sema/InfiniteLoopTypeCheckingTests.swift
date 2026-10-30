#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Sema-surface tests for `while(true)` / `do while(true)` infinite loops.
///
/// KSP-CAP-004: constant-true loops with no `break` targeting the loop are
/// typed as `Nothing`, so functions that return inside the loop (or that have
/// a `Nothing` return type) pass type checking.
@Suite
struct InfiniteLoopTypeCheckingTests {

    @Test func testInfiniteLoopTypeCheckingSema() throws {
        let sources: [String] = [
            // testWhileTrueReturnLoopSatisfiesReturnType
            """
            package sample0
                    fun f(cond: Boolean): Int {
                        while (true) {
                            if (cond) return 1
                        }
                    }

            """,

            // testWhileTrueBreakLoopIsUnit
            """
            package sample1
                    fun f(cond: Boolean) {
                        while (true) {
                            if (cond) break
                        }
                    }

            """,

            // testNothingReturnInfiniteLoop
            """
            package sample2
                    fun never(): Nothing {
                        while (true) {}
                    }

            """,

            // testDoWhileTrueReturnLoopSatisfiesReturnType
            """
            package sample3
                    fun f(cond: Boolean): Int {
                        do {
                            if (cond) return 1
                        } while (true)
                    }

            """,

            // testLabeledWhileTrueBreakIsUnit
            """
            package sample4
                    fun f(cond: Boolean) {
                        loop@ while (true) {
                            if (cond) break@loop
                        }
                    }

            """,

            // testNestedInnerBreakDoesNotReleaseOuterLoop
            """
            package sample5
                    fun f(cond: Boolean): Int {
                        outer@ while (true) {
                            while (true) {
                                if (cond) break
                            }
                        }
                    }

            """,

            // testLocalClassInsideWhileTrueDoesNotCrashBreakScan
            """
            package sample6
                    fun f(cond: Boolean) {
                        while (true) {
                            class Local { fun g() = 1 }
                            if (cond) break
                        }
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testWhileTrueReturnLoopSatisfiesReturnType
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "while(true) with a return inside should satisfy an Int return type: \(sampleDiags.map { $0.message })"
                )
            }
            // testWhileTrueBreakLoopIsUnit
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "while(true) with a break inside should type as Unit: \(sampleDiags.map { $0.message })"
                )
            }
            // testNothingReturnInfiniteLoop
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "while(true) {} should satisfy a Nothing return type: \(sampleDiags.map { $0.message })"
                )
            }
            // testDoWhileTrueReturnLoopSatisfiesReturnType
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "do { ... } while(true) with a return inside should satisfy an Int return type: \(sampleDiags.map { $0.message })"
                )
            }
            // testLabeledWhileTrueBreakIsUnit
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "labeled while(true) with a matching break should type as Unit: \(sampleDiags.map { $0.message })"
                )
            }
            // testNestedInnerBreakDoesNotReleaseOuterLoop
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "inner while(true) break should not make the outer infinite loop Unit-typed: \(sampleDiags.map { $0.message })"
                )
            }
            // testLocalClassInsideWhileTrueDoesNotCrashBreakScan
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "while(true) containing a local class must not crash the break-target scan: \(sampleDiags.map { $0.message })"
                )
            }

        }
    }



    @Test func testDoWhileTerminatingBodySatisfiesReturnType() throws {
        try withTemporaryFile(contents: """
        fun fromBody(): String { do { return "body" } while (false) }
        fun nested(): String { do { while (true) { return "nested" } } while (false) }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DoWhileTerminatingBody", emit: .kirDump)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test(arguments: [
        "fun fromBreak(): String { do { break } while (false) }",
        "fun fromBreak(): String { do { run { break } } while (false) }",
        "fun fromContinue(): String { do { run { continue } } while (false) }",
    ])
    func testDoWhileBreakDoesNotSatisfyReturnType(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DoWhileBreak", emit: .kirDump)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(!errors.isEmpty)
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" }, "\(errors.map(\.message))")
        }
    }

}
#endif
