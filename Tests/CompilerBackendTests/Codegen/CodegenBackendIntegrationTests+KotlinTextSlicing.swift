#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendKotlinTextSlicingEdgeCasesTests {

    @Test func testKotlinTextSubstringEdgeCases() throws {
        let source = """
        fun main() {
            // normal substring
            println("hello world".substring(6))
            println("hello world".substring(0, 5))

            // empty result (start == end)
            println("hello".substring(2, 2))

            // single char
            println("hello".substring(1, 2))

            // whole string
            println("hi".substring(0, 2))

            // substring on empty string, start=0 end=0 OK
            println("".substring(0, 0))

            // out-of-range start: negative
            try {
                println("hello".substring(-1))
            } catch (e: Throwable) {
                println("oob-substring-neg")
            }

            // out-of-range end beyond length
            try {
                println("hello".substring(0, 99))
            } catch (e: Throwable) {
                println("oob-substring-end")
            }

            // start > end
            try {
                println("hello".substring(3, 1))
            } catch (e: Throwable) {
                println("oob-substring-startgtend")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSubstringEdgeCases",
            expected:
                """
                world
                hello

                e
                hi

                oob-substring-neg
                oob-substring-end
                oob-substring-startgtend
                """
                + "\n"
        )
    }

    @Test func testKotlinTextSubSequenceEdgeCases() throws {
        let source = """
        @Suppress("KSWIFTK-SEMA-DEPRECATED")
        fun main() {
            // normal subSequence (delegates to substring)
            println("hello world".subSequence(6, 11))
            println("hello world".subSequence(0, 5))

            // empty result (start == end)
            println("hello".subSequence(2, 2))

            // single char
            println("hello".subSequence(1, 2))

            // whole string
            println("hi".subSequence(0, 2))

            // subSequence on empty string, start=0 end=0 OK
            println("".subSequence(0, 0))

            // out-of-range start: negative
            try {
                println("hello".subSequence(-1, 2))
            } catch (e: Throwable) {
                println("oob-subSequence-neg")
            }

            // out-of-range end beyond length
            try {
                println("hello".subSequence(0, 99))
            } catch (e: Throwable) {
                println("oob-subSequence-end")
            }

            // start > end
            try {
                println("hello".subSequence(3, 1))
            } catch (e: Throwable) {
                println("oob-subSequence-startgtend")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSubSequenceEdgeCases",
            expected:
                """
                world
                hello

                e
                hi

                oob-subSequence-neg
                oob-subSequence-end
                oob-subSequence-startgtend
                """
                + "\n"
        )
    }

    @Test func testKotlinTextCodePointCountEdgeCases() throws {
        let source = """
        fun main() {
            val text = "a😀b"

            println("abc".codePointCount())
            println("😀".codePointCount())
            println(text.codePointCount())
            println(text.codePointCount(1))
            println(text.codePointCount(1, 3))
            println(text.codePointCount(0, 2))
            println(text.codePointCount(endIndex = 3))

            val asSequence: CharSequence = text
            println(asSequence.codePointCount(1, 3))

            try {
                println(text.codePointCount(-1, 1))
            } catch (e: Throwable) {
                println("oob-codepoint-start")
            }

            try {
                println(text.codePointCount(0, 99))
            } catch (e: Throwable) {
                println("oob-codepoint-end")
            }

            try {
                println(text.codePointCount(3, 1))
            } catch (e: Throwable) {
                println("oob-codepoint-order")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCodePointCountEdgeCases",
            expected:
                """
                3
                1
                3
                2
                1
                2
                2
                1
                oob-codepoint-start
                oob-codepoint-end
                oob-codepoint-order
                """
                + "\n"
        )
    }

    @Test func testKotlinTextTrimEdgeCases() throws {
        let source = """
        fun main() {
            // trim on empty string
            println("".trim())

            // trim all whitespace
            println("   ".trim())

            // trim leading only
            println("  hello".trim())

            // trim trailing only
            println("hello  ".trim())

            // trim both ends
            println("  hello  ".trim())

            // trimStart
            println("  hello  ".trimStart())

            // trimEnd
            println("  hello  ".trimEnd())

            // single char string, is whitespace
            println(" ".trim())

            // single char string, not whitespace
            println("a".trim())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextTrimEdgeCases",
            expected:
"\n" +
                "\n" +
                "hello\n" +
                "hello\n" +
                "hello\n" +
                "hello  \n" +
                "  hello\n" +
                "\n" +
                "a\n"
        )
    }

    @Test func testKotlinTextTrimPredicateEdgeCases() throws {
        let source = """
        fun main() {
            println("[" + "xxhelloxy".trim { it == 'x' || it == 'y' } + "]")
            println("[" + "xxhelloxy".trimStart { it == 'x' || it == 'y' } + "]")
            println("[" + "xxhelloxy".trimEnd { it == 'x' || it == 'y' } + "]")
            println("[" + "".trim { it == 'x' } + "]")
            println("[" + "aba".trim { it == 'a' } + "]")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextTrimPredicateEdgeCases",
            expected:
                """
                [hello]
                [helloxy]
                [xxhello]
                []
                [b]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextPadEdgeCases() throws {
        let source = """
        fun main() {
            // padStart: already at desired length (no-op)
            println("hello".padStart(5))

            // padStart: shorter than desired length
            println("hi".padStart(5))

            // padStart: target length < string length (no-op)
            println("hello".padStart(3))

            // padStart with custom pad char
            println("hi".padStart(5, '0'))

            // padEnd: shorter than desired length
            println("hi".padEnd(5))

            // padEnd: already long enough
            println("hello".padEnd(3))

            // padEnd with custom char
            println("hi".padEnd(5, '*'))

            // padStart on empty string
            println("".padStart(3, 'x'))

            // padEnd on empty string
            println("".padEnd(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextPadEdgeCases",
            expected:
                "hello\n" +
                "   hi\n" +
                "hello\n" +
                "000hi\n" +
                "hi   \n" +
                "hello\n" +
                "hi***\n" +
                "xxx\n" +
                "   \n"
        )
    }

    @Test func testKotlinTextTakeDropEdgeCases() throws {
        let source = """
        fun main() {
            // take: normal
            println("hello".take(3))

            // take: n == length
            println("hello".take(5))

            // take: n > length (returns full string)
            println("hello".take(100))

            // take: n == 0 (empty)
            println("hello".take(0))

            // drop: normal
            println("hello".drop(2))

            // drop: n == length (empty)
            println("hello".drop(5))

            // drop: n > length (empty)
            println("hello".drop(100))

            // drop: n == 0 (full string)
            println("hello".drop(0))

            // takeLast: normal
            println("hello".takeLast(3))

            // takeLast: n == length
            println("hello".takeLast(5))

            // takeLast: n > length (full string)
            println("hello".takeLast(100))

            // takeLast: n == 0 (empty)
            println("hello".takeLast(0))

            // dropLast: normal
            println("hello".dropLast(2))

            // dropLast: n == length (empty)
            println("hello".dropLast(5))

            // dropLast: n > length (empty)
            println("hello".dropLast(100))

            // dropLast: n == 0 (full string)
            println("hello".dropLast(0))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextTakeDropEdgeCases",
            expected:
"hel\n" +
                "hello\n" +
                "hello\n" +
                "\n" +
                "llo\n" +
                "\n" +
                "\n" +
                "hello\n" +
                "llo\n" +
                "hello\n" +
                "hello\n" +
                "\n" +
                "hel\n" +
                "\n" +
                "\n" +
                "hello\n"
        )
    }

    @Test func testKotlinTextTakeNegativeThrows() throws {
        // Kotlin spec: take(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".take(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-take")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinTextTakeNegativeThrows", expected: "iae-take\n")
    }

    @Test func testKotlinTextDropNegativeThrows() throws {
        // Kotlin spec: drop(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".drop(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-drop")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinTextDropNegativeThrows", expected: "iae-drop\n")
    }

    @Test func testKotlinTextTakeLastNegativeThrows() throws {
        // Kotlin spec: takeLast(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".takeLast(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-takeLast")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinTextTakeLastNegativeThrows", expected: "iae-takeLast\n")
    }

    @Test func testKotlinTextDropLastNegativeThrows() throws {
        // Kotlin spec: dropLast(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".dropLast(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-dropLast")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinTextDropLastNegativeThrows", expected: "iae-dropLast\n")
    }
}
#endif
