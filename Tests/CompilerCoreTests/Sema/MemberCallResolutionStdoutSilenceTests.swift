@testable import CompilerCore
import Foundation
import Testing

/// Regression test for stray debug output during regular member-call resolution.
///
/// A leftover debug `print("REGULAR ...")` pair in
/// `CallTypeChecker+MemberCallInferenceRegularResolution.swift` used to dump
/// candidate/chosen overload descriptions to the compiler's stdout whenever
/// user code called a member named `sumOf` / `sumBy` / `sumByDouble`. The
/// compiler must not interleave internal resolution traces with its regular
/// output channel.
@Suite
struct MemberCallResolutionStdoutSilenceTests {

    /// Redirects STDOUT to a pipe for the duration of `block` and returns
    /// everything written to it. Same capture pattern as RuntimePrintlnTests.
    private func captureStdout(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test
    func testSemaEmitsNoResolutionTraceForUserDefinedSumMembers() throws {
        let source = """
        package sample

        class Stats {
            fun sumOf(x: Int): Int = x * 2
            fun sumBy(x: Int): Int = x + 1
            fun sumByDouble(x: Double): Double = x
        }

        fun main() {
            val s = Stats()
            println(s.sumOf(21))
            println(s.sumBy(9))
            println(s.sumByDouble(1.5))
        }
        """
        let ctx = makeContextFromSource(source)
        var semaError: Error?
        let output = captureStdout {
            do {
                try runSema(ctx)
            } catch {
                semaError = error
            }
        }
        if let semaError {
            Issue.record("Sema pipeline threw: \(semaError)")
        }
        #expect(
            !(ctx.diagnostics.hasError),
            "expected a clean type-check, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        // Other suites may run in parallel and share the process-wide stdout,
        // so assert on the specific trace prefix instead of full emptiness.
        #expect(
            !output.contains("REGULAR "),
            "member-call resolution leaked a debug trace to stdout: \(output)"
        )
    }
}
