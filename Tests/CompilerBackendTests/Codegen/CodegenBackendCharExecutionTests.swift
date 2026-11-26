#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendCharExecutionTests {

    @Test
    func testNullableCharCodeUnboxesTheReceiverAndBoxesTheIntResult() throws {
        try assertKotlinOutput(
            """
            fun code(value: Char?): Int? = value?.code
            fun main() {
                val value: Char? = 'a'
                val erased: Any? = value?.code
                println(erased is Int)
                println(erased)
                println(code('\\u0000'))
                println(code('\\uD83D'))
                println(code('\\uDE00'))
                println(code('\\uFFFF'))
                println(code(null))
                println(value?.code == 97)
            }
            """,
            moduleName: "NullableCharCode",
            expected: "true\n97\n0\n55357\n56832\n65535\nnull\ntrue\n"
        )
    }

    @Test
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

    @Test
    func testCodegenCharPlusInt() throws {
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

    @Test
    func testCodegenCharMinusInt() throws {
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

    @Test
    func testCodegenCharMinusChar() throws {
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

    @Test
    func testCodegenStringGetByIndex() throws {
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

    @Test
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

    @Test
    func testCodegenCharRangeForEachEmpty() throws {
        let source = """
        fun main() {
            ('e'..'a').forEach { c -> println(c.code) }
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "CharRangeForEachEmpty", expected: "done\n")
    }

    @Test
    func testCodegenCharProgressionForEachDescending() throws {
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

    @Test
    func testCodegenCharIsJavaIdentifierPartTypicalValues() throws {
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

    @Test
    func testCodegenCharIsJavaIdentifierPartDigitAllowedButStartForbids() throws {
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

    @Test
    func testCodegenForLoopStringIterationMemberCall() throws {
        let source = """
        fun main() {
            for (ch in "abc") {
                println(ch.digitToIntOrNull(16))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopStringIterationMemberCall",
            expected:
                """
                10
                11
                12
                """
                + "\n"
        )
    }

    @Test
    func testCodegenForLoopStringIterationExplicitCharType() throws {
        let source = """
        fun main() {
            for (ch in "abc") {
                val x: Char = ch
                println(x.digitToIntOrNull(16))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopStringIterationExplicitCharType",
            expected:
                """
                10
                11
                12
                """
                + "\n"
        )
    }

    @Test
    func testCodegenForLoopUntilRangeIndexedStringCharMemberCall() throws {
        let source = """
        fun main() {
            val hex = "abc"
            for (i in 0 until hex.length) {
                val ch = hex[i]
                println(ch.digitToIntOrNull(16))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopUntilRangeIndexedStringCharMemberCall",
            expected:
                """
                10
                11
                12
                """
                + "\n"
        )
    }

    @Test
    func testCodegenForLoopUntilRangeExplicitIntType() throws {
        let source = """
        fun main() {
            for (i in 0 until 3) {
                val x: Int = i
                println(x)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopUntilRangeExplicitIntType",
            expected:
                """
                0
                1
                2
                """
                + "\n"
        )
    }

    @Test
    func testCodegenForLoopCharRangeExplicitCharType() throws {
        let source = """
        fun main() {
            for (c in 'a'..'e') {
                val x: Char = c
                println(x.code)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopCharRangeExplicitCharType",
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
}
#endif
