@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// KSP-466: A trailing lambda passed to `require`/`check` (lowered via the
/// "legacy" closure-raw ABI in CallLowerer+ClosureAdapters.swift) that
/// captures 2+ distinct locals produced wrong interpolated values, and
/// captures beyond a certain count crashed with an out-of-bounds
/// `kk_array_get_inbounds` panic. Root cause: the call site forwarded only
/// `captureArguments.first` (the raw first captured value) instead of boxing
/// multiple captures into a closure object, while the lambda body always
/// expected a boxed closure object once it had 2+ captures.
extension CodegenBackendIntegrationTests {
    func testCodegenRequireLambdaSingleCaptureInMemberFunctionReturnsCorrectValue() throws {
        let source = """
        class Checker {
            fun check(array: ByteArray, fromIndex: Int): ByteArray {
                require(fromIndex in 0..array.size) {
                    "fromIndex is $fromIndex"
                }
                return array
            }
        }

        fun main() {
            val c = Checker()
            val array = byteArrayOf(1, 2, 3, 4, 5)
            try {
                c.check(array, 9)
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "RequireLambdaSingleCaptureMember", expected: "fromIndex is 9\n")
    }

    func testCodegenRequireLambdaTwoCapturesInMemberFunctionReturnsCorrectValues() throws {
        let source = """
        class Checker {
            fun check(array: ByteArray, fromIndex: Int): ByteArray {
                require(fromIndex in 0..array.size) {
                    "fromIndex ($fromIndex) size is ${array.size}"
                }
                return array
            }
        }

        fun main() {
            val c = Checker()
            val array = byteArrayOf(1, 2, 3, 4, 5)
            try {
                c.check(array, 9)
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RequireLambdaTwoCapturesMember",
            expected: "fromIndex (9) size is 5\n"
        )
    }

    /// This is the exact minimal repro from the KSP-466 bug report: three
    /// distinct captures inside a member function used to crash with
    /// `kk_array_get_inbounds precondition failed`.
    func testCodegenRequireLambdaThreeCapturesInMemberFunctionReturnsCorrectValuesWithoutCrashing() throws {
        let source = """
        class Checker {
            fun check(array: ByteArray, fromIndex: Int, toIndex: Int): ByteArray {
                require(fromIndex in 0..array.size && toIndex in 0..array.size) {
                    "fromIndex ($fromIndex) or toIndex ($toIndex) are out of range: 0..${array.size}."
                }
                array[fromIndex] = 99
                return array
            }
        }

        fun main() {
            val c = Checker()
            val array = byteArrayOf(1, 2, 3, 4, 5)
            try {
                c.check(array, 3, 6)
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RequireLambdaThreeCapturesMember",
            expected: "fromIndex (3) or toIndex (6) are out of range: 0..5.\n"
        )
    }

    func testCodegenRequireLambdaFourCapturesInTopLevelFunctionReturnsCorrectValuesWithoutCrashing() throws {
        let source = """
        fun check(array: ByteArray, fromIndex: Int, toIndex: Int, extra: Int): ByteArray {
            require(fromIndex in 0..array.size && toIndex in 0..array.size) {
                "fromIndex ($fromIndex) toIndex ($toIndex) extra ($extra) size is ${array.size}."
            }
            return array
        }

        fun main() {
            val array = byteArrayOf(1, 2, 3, 4, 5)
            try {
                check(array, 3, 6, 42)
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RequireLambdaFourCapturesTopLevel",
            expected: "fromIndex (3) toIndex (6) extra (42) size is 5.\n"
        )
    }

    func testCodegenCheckLambdaMultipleCapturesInMemberFunctionReturnsCorrectValues() throws {
        let source = """
        class Validator {
            var state = 0

            fun validate(name: String, minLen: Int, maxLen: Int): String {
                check(name.length in minLen..maxLen) {
                    "name '$name' (len=${name.length}) must be between $minLen and $maxLen"
                }
                return name
            }
        }

        fun main() {
            val v = Validator()
            try {
                v.validate("hi", 5, 10)
            } catch (e: IllegalStateException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CheckLambdaMultiCaptureMember",
            expected: "name 'hi' (len=2) must be between 5 and 10\n"
        )
    }
}
