// TEST-CHAR-019: End-to-end execution tests for Char arithmetic and CharRange.forEach.
// Char.plus(Int) and Char.minus(Int) have no dedicated runtime symbol — they lower to
// kk_op_add/kk_op_sub via the IR, so codegen is the only layer that can verify them.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testCodegenCharIsISOControlBoundaries() throws {
        let source = """
        fun main() {
            println('\\u001f'.isISOControl())
            println(' '.isISOControl())
            println('\\u007f'.isISOControl())
            println('\\u009f'.isISOControl())
            println('\\u00a0'.isISOControl())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharIsISOControlExecution",
            expected:
                """
                true
                false
                true
                true
                false
                """
                + "\n"
        )
    }

    func testCodegenCharPlusInt() throws {
        // Char.plus(Int) lowers to kk_op_add; .code extracts the result as Int for safe printing
        let source = """
        fun main() {
            println(('a' + 1).code)
            println(('A' + 25).code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharPlusIntExecution",
            expected:
                """
                98
                90
                """
                + "\n"
        )
    }

    func testCodegenCharMinusInt() throws {
        // Char.minus(Int) lowers to kk_op_sub; result type is Char, printed via .code
        let source = """
        fun main() {
            println(('b' - 1).code)
            println(('z' - 25).code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharMinusIntExecution",
            expected:
                """
                97
                97
                """
                + "\n"
        )
    }

    func testCodegenCharMinusChar() throws {
        // Char.minus(Char) dispatches to kk_char_minus and returns Int
        let source = """
        fun main() {
            println('b' - 'a')
            println('a' - 'b')
            println('z' - 'a')
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharMinusCharExecution",
            expected:
                """
                1
                -1
                25
                """
                + "\n"
        )
    }

    func testCodegenStringGetByIndex() throws {
        // String.get dispatches to kk_string_get; result is Char, printed via .code
        let source = """
        fun main() {
            println("hello"[1].code)
            println("world"[0].code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringGetIndexExecution",
            expected:
                """
                101
                119
                """
                + "\n"
        )
    }

    func testCodegenCharRangeForEachAscending() throws {
        let source = """
        fun main() {
            ('a'..'e').forEach { c -> println(c.code) }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharRangeForEachAscending",
            expected:
                """
                97
                98
                99
                100
                101
                """
                + "\n"
        )
    }

    func testCodegenCharRangeForEachEmpty() throws {
        // ('e'..'a') with implicit step=1 — first > last, so forEach iterates zero times
        let source = """
        fun main() {
            ('e'..'a').forEach { c -> println(c.code) }
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "CharRangeForEachEmpty", expected: "done\n")
    }

    func testCodegenCharProgressionForEachDescending() throws {
        // 'e' downTo 'a' produces a CharProgression with step=-1
        let source = """
        fun main() {
            ('e' downTo 'a').forEach { c -> println(c.code) }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharProgressionForEachDescending",
            expected:
                """
                101
                100
                99
                98
                97
                """
                + "\n"
        )
    }

    func testCodegenCharIsJavaIdentifierPartTypicalValues() throws {
        // Covers letters, digits, connector punctuation (_), currency symbol ($),
        // and characters that are NOT valid identifier parts (space, operator).
        let source = """
        fun main() {
            println('A'.isJavaIdentifierPart())
            println('5'.isJavaIdentifierPart())
            println('_'.isJavaIdentifierPart())
            println('$'.isJavaIdentifierPart())
            println(' '.isJavaIdentifierPart())
            println('+'.isJavaIdentifierPart())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharIsJavaIdentifierPartTypical",
            expected:
                """
                true
                true
                true
                true
                false
                false
                """
                + "\n"
        )
    }

    func testCodegenCharIsJavaIdentifierPartDigitAllowedButStartForbids() throws {
        // Digits are valid identifier *parts* but NOT valid identifier *starts*.
        // This test documents the semantic difference between the two predicates
        // and ensures both runtime symbols are wired correctly through codegen.
        let source = """
        fun main() {
            println('5'.isJavaIdentifierPart())
            println('5'.isJavaIdentifierStart())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharIsJavaIdentifierPartVsStart",
            expected:
                """
                true
                false
                """
                + "\n"
        )
    }
}

