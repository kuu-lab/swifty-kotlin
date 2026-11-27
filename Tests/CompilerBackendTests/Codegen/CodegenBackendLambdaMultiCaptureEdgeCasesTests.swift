#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendLambdaMultiCaptureEdgeCasesTests {

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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
#endif
