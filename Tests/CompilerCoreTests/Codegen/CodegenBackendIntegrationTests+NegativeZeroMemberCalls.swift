@testable import CompilerCore
import Foundation
import XCTest

// SPEC-NUM-0008: Primitive Double/Float member-call edge cases around negative zero.
//
// Root cause: -0.0 (Double) has IEEE 754 bit pattern 0x8000000000000000 == Int.min
// == runtimeNullSentinelInt.  kk_any_to_string previously checked the null sentinel
// before dispatching on the float/double tag, so (-0.0).toString() incorrectly
// returned "null".  Fixes:
//   1. Tags 5/6 (float/double) in kk_any_to_string are now checked first.
//   2. runtimeFormatFloatingPoint gained an explicit -0.0 guard in case
//      String(describing:) drops the sign bit on a particular Swift toolchain.
//   3. Float.compareTo is exercised alongside Double to rule out link errors.
extension CodegenBackendIntegrationTests {
    private func assertNegZeroStdout(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, expected)
        }
    }

    /// (-0.0).toString() must return "-0.0", not "null".
    /// Regression for SPEC-NUM-0008 bug #2: null-sentinel collision.
    func testNegativeZeroDoubleToString() throws {
        let source = """
        fun main() {
            println((-0.0).toString())
            val z: Double = -0.0
            println(z.toString())
        }
        """
        try assertNegZeroStdout(source, moduleName: "NegZeroDoubleToString", expected: "-0.0\n-0.0\n")
    }

    /// (-0.0f).toString() must return "-0.0", not "null".
    func testNegativeZeroFloatToString() throws {
        let source = """
        fun main() {
            println((-0.0f).toString())
            val z: Float = -0.0f
            println(z.toString())
        }
        """
        try assertNegZeroStdout(source, moduleName: "NegZeroFloatToString", expected: "-0.0\n-0.0\n")
    }

    /// A function returning -0.0 must print "-0.0" in the caller, not "0.0" or "null".
    /// Regression for SPEC-NUM-0008 bug #3: sign loss in return-value path.
    func testNegativeZeroReturnValue() throws {
        let source = """
        fun negZeroDouble(): Double = -0.0
        fun negZeroFloat(): Float = -0.0f
        fun main() {
            println(negZeroDouble())
            println(negZeroFloat())
        }
        """
        try assertNegZeroStdout(source, moduleName: "NegZeroReturnValue", expected: "-0.0\n-0.0\n")
    }
}
