@testable import CompilerCore
import Foundation
import XCTest

//

extension CodegenBackendIntegrationTests {

    func testKotlinTextSplitEdgeCases() throws {
        let source = """
        fun main() {
            // empty string with single-char delimiter
            println("".split(","))

            // no delimiter in string
            println("hello".split(","))

            // single-char delimiter
            println("a,b,c".split(","))

            // multi-char delimiter
            println("aXXbXXc".split("XX"))

            // delimiter at start and end (trailing empty parts)
            println(",a,b,".split(","))

            // consecutive delimiters
            println("a,,b".split(","))

            // entire string is delimiter
            println(",".split(","))

            // empty delimiter returns list containing original string
            println("abc".split(""))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitEdgeCases",
            expected:
                """
                []
                [hello]
                [a, b, c]
                [a, b, c]
                [, a, b, ]
                [a, , b]
                [, ]
                [abc]
                """
                + "\n"
        )
    }

    func testKotlinTextSplitWithLimitEdgeCases() throws {
        let source = """
        fun main() {
            println("a,b,c,d".split(",", limit = 2))
            println("a,b,c".split(",", limit = 0))
            println("a,b,c".split(",", limit = -1))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitWithLimitEdgeCases",
            expected:
                """
                [a, b,c,d]
                [a, b, c]
                [a, b, c]
                """
                + "\n"
        )
    }

    func testKotlinTextSplitToSequenceEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".splitToSequence(",").toList())

            // no delimiter present
            println("hello".splitToSequence(",").toList())

            // normal split
            println("a,b,c".splitToSequence(",").toList())

            // empty delimiter returns original string wrapped
            println("abc".splitToSequence("").toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitToSeqEdgeCases",
            expected:
                """
                []
                [hello]
                [a, b, c]
                [abc]
                """
                + "\n"
        )
    }

    func testKotlinTextToMutableListEdgeCases() throws {
        let source = """
        fun main() {
            // empty string -> empty mutable list
            println("".toMutableList())

            // single char
            println("a".toMutableList())

            // multiple chars
            println("abc".toMutableList())

            // result is mutable: add grows the list, removeAt shrinks it
            val chars = "abc".toMutableList()
            chars.add('d')
            println(chars.size)
            chars.removeAt(3)
            println(chars)
            chars.removeAt(0)
            println(chars)
            println(chars.size)

            // each call returns an independent copy
            val a = "xy".toMutableList()
            val b = "xy".toMutableList()
            a.add('z')
            println(a.size)
            println(b.size)
            println(b)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextToMutableListEdgeCases",
            expected:
                """
                []
                [a]
                [a, b, c]
                4
                [a, b, c]
                [b, c]
                2
                3
                2
                [x, y]
                """
                + "\n"
        )
    }

    func testKotlinTextFirstNotNullOfEdgeCases() throws {
        let source = """
        fun firstFromSequence(value: CharSequence): String {
            return value.firstNotNullOf<String> { ch -> if (ch == 'b') "bee" else null }
        }

        fun main() {
            println(firstFromSequence("abc"))
            println("kotlin".firstNotNullOf<String> { ch -> if (ch == 't') "tea" else null })
            try {
                println("abc".firstNotNullOf<String> { ch -> null })
            } catch (e: Throwable) {
                println("missing")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFirstNotNullOfEdgeCases",
            expected:
                """
                bee
                tea
                missing
                """
                + "\n"
        )
    }

    func testKotlinTextFirstNotNullOfOrNullEdgeCases() throws {
        let source = """
        fun firstFromSequence(value: CharSequence): String? {
            return value.firstNotNullOfOrNull<String> { ch -> if (ch == 'b') "bee" else null }
        }

        fun main() {
            println(firstFromSequence("abc"))
            println("kotlin".firstNotNullOfOrNull<String> { ch -> if (ch == 't') "tea" else null })
            println("abc".firstNotNullOfOrNull<String> { ch -> null } ?: "missing")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFirstNotNullOfOrNullEdgeCases",
            expected:
                """
                bee
                tea
                missing
                """
                + "\n"
        )
    }

    func testKotlinTextReduceRightIndexedEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char {
            return value.reduceRightIndexed { index, ch, acc -> if (index == 1) ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc"))
            println("abcd".reduceRightIndexed { index, ch, acc -> if (index == 0) ch else acc })
            try {
                println("".reduceRightIndexed { index, ch, acc -> if (index == 0) ch else acc })
            } catch (e: Throwable) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReduceRightIndexedEdgeCases",
            expected:
                """
                b
                a
                empty
                """
                + "\n"
        )
    }

    func testKotlinTextReduceRightIndexedOrNullEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceRightIndexedOrNull { index, ch, acc -> if (index == 1) ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc") ?: 'x')
            println("abcd".reduceRightIndexedOrNull { index, ch, acc -> if (index == 0) ch else acc } ?: 'x')
            println("".reduceRightIndexedOrNull { index, ch, acc -> if (index == 0) ch else acc } ?: 'x')
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReduceRightIndexedOrNullEdgeCases",
            expected:
                """
                b
                a
                x
                """
                + "\n"
        )
    }

    func testKotlinTextReduceRightOrNullEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceRightOrNull { ch, acc -> if (ch == 'b') ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc") ?: 'x')
            println("abcd".reduceRightOrNull { ch, acc -> if (ch == 'a') ch else acc } ?: 'x')
            println("".reduceRightOrNull { ch, acc -> if (ch == 'a') ch else acc } ?: 'x')
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReduceRightOrNullEdgeCases",
            expected:
                """
                b
                a
                x
                """
                + "\n"
        )
    }

    func testKotlinTextSumByEdgeCases() throws {
        let source = """
        fun sumFromSequence(value: CharSequence): Int {
            return value.sumBy { if (it == 'a') 10 else 1 }
        }

        fun main() {
            println(sumFromSequence("aba"))
            println("bbb".sumBy { ch -> if (ch == 'b') 3 else 0 })
            println("".sumBy { 1 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSumByEdgeCases",
            expected:
                """
                21
                9
                0
                """
                + "\n"
        )
    }

    func testKotlinTextSumByDoubleEdgeCases() throws {
        let source = """
        fun sumFromSequence(value: CharSequence): Double {
            return value.sumByDouble { if (it == 'a') 1.5 else 0.25 }
        }

        fun main() {
            println(sumFromSequence("aba"))
            println("bbb".sumByDouble { ch -> if (ch == 'b') 2.0 else 0.0 })
            println("".sumByDouble { 1.0 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSumByDoubleEdgeCases",
            expected:
                """
                3.25
                6.0
                0.0
                """
                + "\n"
        )
    }

    func testKotlinTextReplaceEdgeCases() throws {
        let source = """
        fun main() {
            // replace in empty string
            println("".replace("a", "b"))

            // replace non-existing substring (no-op)
            println("hello".replace("x", "y"))

            // replace all occurrences: "aababab" has 3 "ab" → "aXXX"
            println("aababab".replace("ab", "X"))

            // replace with empty new value (deletion)
            println("hello".replace("l", ""))

            // replace with empty old value (no-op on empty string)
            println("".replace("", "x"))

            // replaceFirst: only first occurrence changed
            println("aabaa".replaceFirst("a", "Z"))

            // replaceFirst: substring not found (no-op)
            println("hello".replaceFirst("x", "y"))

            // replaceFirst: empty string, no-op
            println("".replaceFirst("a", "b"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceEdgeCases",
            expected:
                """

                hello
                aXXX
                heo

                Zabaa
                hello

                """
                + "\n"
        )
    }

    func testKotlinTextReplaceRangeEdgeCases() throws {
        let source = """
        fun main() {
            // normal replace range
            println("abcde".replaceRange(1..3, "XY"))

            // replace empty range (insertion)
            println("abcde".replaceRange(2..1, "Z"))

            // replace whole string
            println("abc".replaceRange(0..2, "XYZ"))

            // out-of-range start: should throw
            try {
                println("abc".replaceRange(5..5, "X"))
            } catch (e: Throwable) {
                println("oob-replaceRange-start")
            }

            // out-of-range end: should throw
            try {
                println("abc".replaceRange(0..10, "X"))
            } catch (e: Throwable) {
                println("oob-replaceRange-end")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceRangeEdgeCases",
            expected:
                """
                aXYe
                abZcde
                XYZ
                oob-replaceRange-start
                oob-replaceRange-end
                """
                + "\n"
        )
    }

    func testKotlinTextReplaceAfterEdgeCases() throws {
        let source = """
        fun main() {
            println("a:b:c".replaceAfter(":", "X", "MISS"))
            println("abc".replaceAfter(":", "X", "MISS"))
            println("abc".replaceAfter(":", "X"))
            println("abc".replaceAfter("", "X", "MISS"))
            println("abc".replaceAfter("abc", "X", "MISS"))
            println("abc".replaceAfter("c", "X", "MISS"))
            println("a:b:c".replaceAfter(':', "X", "MISS"))
            println("abc".replaceAfter(':', "X", "MISS"))
            println("abc".replaceAfter(':', "X"))
            println("abc".replaceAfter('a', "X", "MISS"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceAfterEdgeCases",
            expected:
                """
                a:X
                MISS
                abc
                X
                abcX
                abcX
                a:X
                MISS
                abc
                aX
                """
                + "\n"
        )
    }

    func testKotlinTextReplaceAfterLastEdgeCases() throws {
        let source = """
        fun main() {
            println("a:b:c".replaceAfterLast(":", "X", "MISS"))
            println("abc".replaceAfterLast(":", "X", "MISS"))
            println("abc".replaceAfterLast(":", "X"))
            println("abc".replaceAfterLast("", "X", "MISS"))
            println("".replaceAfterLast("", "X", "MISS"))
            println("abc".replaceAfterLast("abc", "X", "MISS"))
            println("abc".replaceAfterLast("c", "X", "MISS"))
            println("a:b:c".replaceAfterLast(':', "X", "MISS"))
            println("abc".replaceAfterLast(':', "X", "MISS"))
            println("abc".replaceAfterLast(':', "X"))
            println("abc".replaceAfterLast('a', "X", "MISS"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceAfterLastEdgeCases",
            expected:
                """
                a:b:X
                MISS
                abc
                abX
                MISS
                abcX
                abcX
                a:b:X
                MISS
                abc
                aX
                """
                + "\n"
        )
    }

    func testKotlinTextReplaceBeforeEdgeCases() throws {
        let source = """
        fun main() {
            println("a:b:c".replaceBefore(":", "X", "MISS"))
            println("abc".replaceBefore(":", "X", "MISS"))
            println("abc".replaceBefore(":", "X"))
            println("abc".replaceBefore("", "X", "MISS"))
            println("".replaceBefore("", "X", "MISS"))
            println("abc".replaceBefore("abc", "X", "MISS"))
            println("abc".replaceBefore("a", "X", "MISS"))
            println("a:b:c".replaceBefore(':', "X", "MISS"))
            println("abc".replaceBefore(':', "X", "MISS"))
            println("abc".replaceBefore(':', "X"))
            println("abc".replaceBefore('c', "X", "MISS"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceBeforeEdgeCases",
            expected:
                """
                X:b:c
                MISS
                abc
                Xabc
                X
                Xabc
                Xabc
                X:b:c
                MISS
                abc
                Xc
                """
                + "\n"
        )
    }

    func testKotlinTextReplaceBeforeLastEdgeCases() throws {
        let source = """
        fun main() {
            println("a:b:c".replaceBeforeLast(":", "X", "MISS"))
            println("abc".replaceBeforeLast(":", "X", "MISS"))
            println("abc".replaceBeforeLast(":", "X"))
            println("abc".replaceBeforeLast("", "X", "MISS"))
            println("".replaceBeforeLast("", "X", "MISS"))
            println("abc".replaceBeforeLast("abc", "X", "MISS"))
            println("abc".replaceBeforeLast("a", "X", "MISS"))
            println("a:b:c".replaceBeforeLast(':', "X", "MISS"))
            println("abc".replaceBeforeLast(':', "X", "MISS"))
            println("abc".replaceBeforeLast(':', "X"))
            println("abc".replaceBeforeLast('c', "X", "MISS"))
            println("abc".replaceBeforeLast('a', "X", "MISS"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceBeforeLastEdgeCases",
            expected:
                """
                X:c
                MISS
                abc
                Xc
                MISS
                Xabc
                Xabc
                X:c
                MISS
                abc
                Xc
                Xabc
                """
                + "\n"
        )
    }

    func testKotlinTextReplaceIndentByMarginEdgeCases() throws {
        let source = """
        fun marker(value: String) {
            println(value.replace("\\n", "/"))
        }

        fun main() {
            marker("\\n    |alpha\\n    |  beta\\n    gamma\\n".replaceIndentByMargin("> ", "|"))
            marker("\\n    |alpha\\n    |\\n    |beta\\n".replaceIndentByMargin("--", "|"))
            marker("  >left\\n    >right".replaceIndentByMargin("--", ">"))
            marker("|alpha\\n|beta".replaceIndentByMargin())
            marker("|alpha\\n|beta".replaceIndentByMargin(">>"))
            marker("plain\\n  |mark".replaceIndentByMargin("++", "|"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReplaceIndentByMarginEdgeCases",
            expected:
                """
                > alpha/>   beta/    gamma
                --alpha/--/--beta
                --left/--right
                alpha/beta
                >>alpha/>>beta
                plain/++mark
                """
                + "\n"
        )
    }

    func testKotlinTextSubstringEdgeCases() throws {
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

    func testKotlinTextSubSequenceEdgeCases() throws {
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


    func testKotlinTextCodePointCountEdgeCases() throws {
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

    func testKotlinTextTrimEdgeCases() throws {
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

    func testKotlinTextTrimPredicateEdgeCases() throws {
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

    func testKotlinTextPadEdgeCases() throws {
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

    func testKotlinTextIndexOfEdgeCases() throws {
        let source = """
        fun main() {
            // indexOf: found
            println("hello world".indexOf("world"))

            // indexOf: not found
            println("hello".indexOf("xyz"))

            // indexOf: empty string target (always returns 0)
            println("hello".indexOf(""))

            // indexOf: empty source
            println("".indexOf("x"))

            // indexOf with startIndex
            println("abcabc".indexOf("a", 1))

            // indexOf with startIndex at end
            println("abc".indexOf("c", 3))

            // lastIndexOf: found
            println("abcabc".lastIndexOf("a"))

            // lastIndexOf: not found
            println("hello".lastIndexOf("x"))

            // lastIndexOf: empty target (returns length)
            println("hello".lastIndexOf(""))

            // lastIndexOf on empty source
            println("".lastIndexOf("x"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfEdgeCases",
            expected:
                """
                6
                -1
                0
                -1
                3
                -1
                3
                -1
                5
                -1
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase (positional 3-arg API)
    func testKotlinTextIndexOfIgnoreCaseEdgeCases() throws {
        let source = """
        fun main() {
            println("Hello".indexOf("hello", 0, true))
            println("Hello".lastIndexOf("LO", 4, true))
            println("Hello".indexOf("xyz", 0, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfIgnoreCaseEdgeCases",
            expected:
                """
                0
                3
                -1
                """
                + "\n"
        )
    }

    func testKotlinTextLastIndexOfCharEdgeCases() throws {
        let source = """
        fun main() {
            val text: CharSequence = "Kotlin"
            println(text.lastIndexOf('o', 5, false))
            println(text.lastIndexOf('k', 5, true))
            println("hello".lastIndexOf('l', 4, false))
            println("hello".lastIndexOf('l', 2, false))
            println("hello".lastIndexOf('l', 1, false))
            println("hello".lastIndexOf('x', 4, false))
            println("hello".lastIndexOf('H', 4, true))
            println("".lastIndexOf('a', 0, false))
            println("abc".lastIndexOf('a', -1, false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLastIndexOfCharEdgeCases",
            expected:
                """
                1
                0
                3
                2
                -1
                -1
                0
                -1
                -1
                """
                + "\n"
        )
    }


    func testKotlinTextIndexOfFirstPredicateEdgeCases() throws {
        let source = """
        fun findInParam(s: String): Int {
            return s.indexOfFirst { it == 'l' }
        }

        fun main() {
            // first matching char found
            println("hello".indexOfFirst { it == 'l' })

            // no match returns -1
            println("hello".indexOfFirst { it == 'z' })

            // first char matches: returns 0
            println("abc".indexOfFirst { it == 'a' })

            // last char matches: returns length - 1
            println("abc".indexOfFirst { it == 'c' })

            // empty string: returns -1
            println("".indexOfFirst { it == 'x' })

            // via function parameter (CharSequence receiver)
            println(findInParam("hello world"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfFirstPredicateEdgeCases",
            expected:
                """
                2
                -1
                0
                2
                -1
                2
                """
                + "\n"
        )
    }

    func testKotlinTextChunkedEdgeCases() throws {
        let source = """
        fun main() {
            // normal chunked
            println("abcdef".chunked(2))

            // chunk size larger than string (returns one chunk)
            println("abc".chunked(10))

            // chunk size equals string length
            println("abc".chunked(3))

            // chunked on empty string
            println("".chunked(3))

            // chunk size of 1
            println("abc".chunked(1))

            // windowed: default (step=1)
            println("abcde".windowed(3))

            // windowed: step=2
            println("abcde".windowed(3, 2))

            // windowed: size > string (empty result)
            println("ab".windowed(5))

            // windowed on empty string
            println("".windowed(2))

            // windowed with partialWindows=true
            println("abcd".windowed(3, 2, partialWindows = true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedEdgeCases",
            expected:
                """
                [ab, cd, ef]
                [abc]
                [abc]
                []
                [a, b, c]
                [abc, bcd, cde]
                [abc, cde]
                []
                []
                [abc, cd]
                """
                + "\n"
        )
    }

    func testKotlinTextChunkedSequenceTransformEdgeCases() throws {
        let source = """
        fun main() {
            val lengths: kotlin.sequences.Sequence<Int> =
                "abcdef".chunkedSequence(2) { _: CharSequence -> 2 }
            println(lengths.toList())

            val text: CharSequence = "abcde"
            println(text.chunkedSequence(2) { _: CharSequence -> "chunk" }.toList())

            println("".chunkedSequence(3) { _: CharSequence -> 1 }.toList())
            println("abc".chunkedSequence(10) { _: CharSequence -> "single" }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedSequenceTransformEdgeCases",
            expected:
                """
                [2, 2, 2]
                [chunk, chunk, chunk]
                []
                [single]
                """
                + "\n"
        )
    }

    func testKotlinTextChunkedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size).toList()
        }

        fun renderTransform(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size) { chunk -> "" + chunk + "!" }.toList()
        }

        fun main() {
            println("abcdef".chunkedSequence(2).toList())

            val text: CharSequence = "abcde"
            val chunks: kotlin.sequences.Sequence<String> = text.chunkedSequence(2)
            println(chunks.toList())

            println("".chunkedSequence(3).toList())
            println("abc".chunkedSequence(10).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedSequenceEdgeCases",
            expected:
                """
                [ab, cd, ef]
                [ab, cd, e]
                []
                [abc]
                """
                + "\n"
        )
    }

    func testKotlinTextWindowedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int, step: Int, partial: Boolean): List<String> {
            return value.windowedSequence(size, step, partial).toList()
        }

        fun main() {
            println(render("abcdef", 3, 2, false))
            println(render("abcdef", 3, 2, true))
            println(render("ab", 5, 1, false))
            println(render("ab", 5, 1, true))
            println("hello".windowedSequence(2, 1, false).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedSequenceEdgeCases",
            expected:
                """
                [abc, cde]
                [abc, cde, ef]
                []
                [ab, b]
                [he, el, ll, lo]
                """
                + "\n"
        )
    }

    func testKotlinTextWindowedSequenceTransformEdgeCases() throws {
        let source = """
        fun lengths(value: CharSequence): List<Int> {
            return value.windowedSequence(3, 2, true) { it.length }.toList()
        }

        fun tagged(value: String): List<String> {
            return value.windowedSequence(size = 2, step = 1, partialWindows = false) { window -> "" + window + "!" }.toList()
        }

        fun main() {
            println(lengths("abcdef"))
            println("ab".windowedSequence(5, 1, true) { it.length }.toList())
            println(tagged("hello"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedSequenceTransformEdgeCases",
            expected:
                """
                [3, 3, 2]
                [2, 1]
                [he!, el!, ll!, lo!]
                """
                + "\n"
        )
    }

    func testKotlinTextIndexOfAnyCharsEdgeCases() throws {
        let source = """
        fun firstAny(value: CharSequence, chars: CharArray, start: Int, ignore: Boolean): Int {
            return value.indexOfAny(chars, start, ignore)
        }

        fun main() {
            println(firstAny("Kotlin", charArrayOf('t', 'x'), 0, false))
            println(firstAny("Kotlin", charArrayOf('k'), 0, true))
            println(firstAny("abc", charArrayOf('x'), 0, false))
            println(firstAny("abc", charArrayOf('a'), 5, false))
            println("abc".indexOfAny(charArrayOf('B'), 0, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfAnyCharsEdgeCases",
            expected:
                """
                2
                0
                -1
                -1
                1
                """
                + "\n"
        )
    }

    func testKotlinTextIndexOfAnyStringsEdgeCases() throws {
        let source = """
        fun firstAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Int {
            return value.indexOfAny(strings, start, ignore)
        }

        fun main() {
            println(firstAny("Kotlin", listOf("lin", "zz"), 0, false))
            println(firstAny("Kotlin", listOf("ko"), 0, true))
            println("abc".indexOfAny(listOf("x", "bc"), 0, false))
            println("abc".indexOfAny(listOf(""), 2, false))
            println("abc".indexOfAny(listOf("a"), 5, false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfAnyStringsEdgeCases",
            expected:
                """
                3
                0
                1
                2
                -1
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-021: indexOfAny with default arguments (startIndex=0, ignoreCase=false)
    func testKotlinTextIndexOfAnyDefaultArgs() throws {
        let source = """
        fun main() {
            val text = "Kotlin"
            println(text.indexOfAny(charArrayOf('t', 'K')))
            println(text.indexOfAny(charArrayOf('t', 'K'), 2))
            println(text.indexOfAny(listOf("otl", "zz")))
            println(text.indexOfAny(listOf("otl"), 2))
            println("abc".indexOfAny(charArrayOf('x')))
            println("abc".indexOfAny(listOf("bc")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIndexOfAnyDefaultArgs",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                0
                2
                1
                -1
                -1
                1
                """
                + "\n"
            )
        }
    }

    func testKotlinTextLastIndexOfAnyCharsEdgeCases() throws {
        let source = """
        fun lastAny(value: CharSequence, chars: CharArray, start: Int, ignore: Boolean): Int {
            return value.lastIndexOfAny(chars, start, ignore)
        }

        fun main() {
            println(lastAny("Kotlin", charArrayOf('t', 'o'), 5, false))
            println(lastAny("Kotlin", charArrayOf('k'), 5, true))
            println("abca".lastIndexOfAny(charArrayOf('a'), 2, false))
            println("abc".lastIndexOfAny(charArrayOf('x'), 2, false))
            println("abc".lastIndexOfAny(charArrayOf('C'), 2, true))
            println("abc".lastIndexOfAny(charArrayOf('a'), -1, false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLastIndexOfAnyCharsEdgeCases",
            expected:
                """
                2
                0
                0
                -1
                2
                -1
                """
                + "\n"
        )
    }

    func testKotlinTextLastIndexOfAnyStringsEdgeCases() throws {
        let source = """
        fun lastAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Int {
            return value.lastIndexOfAny(strings, start, ignore)
        }

        fun main() {
            println(lastAny("Kotlin", listOf("ot", "li"), 5, false))
            println(lastAny("Kotlin", listOf("KO"), 5, true))
            println("abc".lastIndexOfAny(listOf("x", "bc"), 2, false))
            println("abc".lastIndexOfAny(listOf(""), 5, false))
            println("abc".lastIndexOfAny(listOf(""), 2, false))
            println("abc".lastIndexOfAny(listOf("a"), -1, false))
            println("abc".lastIndexOfAny(listOf("C"), 2, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLastIndexOfAnyStringsEdgeCases",
            expected:
                """
                3
                0
                1
                3
                2
                -1
                2
                """
                + "\n"
        )
    }

    func testKotlinTextFindAnyOfStringsEdgeCases() throws {
        let source = """
        fun findAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Pair<Int, String>? {
            return value.findAnyOf(strings, start, ignore)
        }

        fun render(match: Pair<Int, String>?): String {
            if (match == null) return "null"
            return match.first.toString() + ":" + match.second
        }

        fun main() {
            println(render(findAny("Kotlin", listOf("lin", "ot"), 0, false)))
            println(render(findAny("Kotlin", listOf("KO"), 0, true)))
            println(render("abc".findAnyOf(listOf("x", "bc"), 0, false)))
            println(render("abc".findAnyOf(listOf(""), 5, false)))
            println(render("abc".findAnyOf(listOf("a"), 5, false)))
            println(render("abc".findAnyOf(listOf("bc", "b"), 0, false)))
            println(render("abc".findAnyOf(listOf("a"), -1, false)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFindAnyOfStringsEdgeCases",
            expected:
                """
                1:ot
                0:KO
                1:bc
                3:
                null
                1:bc
                0:a
                """
                + "\n"
        )
    }

    func testKotlinTextFindLastAnyOfStringsEdgeCases() throws {
        let source = """
        fun findLastAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Pair<Int, String>? {
            return value.findLastAnyOf(strings, start, ignore)
        }

        fun render(match: Pair<Int, String>?): String {
            if (match == null) return "null"
            return match.first.toString() + ":" + match.second
        }

        fun main() {
            println(render(findLastAny("Kotlin", listOf("ot", "li"), 5, false)))
            println(render(findLastAny("Kotlin", listOf("KO"), 5, true)))
            println(render("abc".findLastAnyOf(listOf("x", "bc"), 2, false)))
            println(render("abc".findLastAnyOf(listOf(""), 5, false)))
            println(render("abc".findLastAnyOf(listOf(""), 2, false)))
            println(render("abc".findLastAnyOf(listOf("a"), -1, false)))
            println(render("abc".findLastAnyOf(listOf("C"), 2, true)))
            println(render("abc".findLastAnyOf(listOf("bc", "b"), 2, false)))
            println(render("abc".findLastAnyOf(listOf("a"), 5, false)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFindLastAnyOfStringsEdgeCases",
            expected:
                """
                3:li
                0:KO
                1:bc
                3:
                2:
                null
                2:C
                1:bc
                0:a
                """
                + "\n"
        )
    }

    func testKotlinTextLinesEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".lines())

            // single line (no newline)
            println("hello".lines())

            // trailing newline — runtime includes trailing empty element
            println("hello\\n".lines())

            // CRLF line endings
            println("a\\r\\nb\\r\\nc".lines())

            // mixed line endings (\n and \r)
            println("a\\nb\\rc".lines())

            // only newlines
            println("\\n\\n".lines())

            // single newline
            println("\\n".lines())

            // Windows CRLF only
            println("\\r\\n".lines())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLinesEdgeCases",
            expected:
"[]\n" +
                "[hello]\n" +
                "[hello, ]\n" +
                "[a, b, c]\n" +
                "[a, b, c]\n" +
                "[, , ]\n" +
                "[, ]\n" +
                "[, ]\n"
        )
    }

    func testKotlinTextRemovePrefixSuffixEdgeCases() throws {
        let source = """
        fun main() {
            // removePrefix: present
            println("foobar".removePrefix("foo"))

            // removePrefix: not present (no-op)
            println("hello".removePrefix("world"))

            // removePrefix: empty prefix (no-op)
            println("hello".removePrefix(""))

            // removePrefix: entire string is prefix
            println("hello".removePrefix("hello"))

            // removeSuffix: present
            println("foobar".removeSuffix("bar"))

            // removeSuffix: not present (no-op)
            println("hello".removeSuffix("world"))

            // removeSuffix: empty suffix (no-op)
            println("hello".removeSuffix(""))

            // removeSuffix: entire string is suffix
            println("hello".removeSuffix("hello"))

            // on empty string
            println("".removePrefix("x"))
            println("".removeSuffix("x"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextRemovePrefixSuffixEdgeCases",
            expected:
                """
                bar
                hello
                hello

                foo
                hello
                hello



                """
                + "\n"
        )
    }

    func testKotlinTextRemovePrefixSuffixCharSequenceEdgeCases() throws {
        let source = """
        fun trimPrefix(value: CharSequence): String {
            return value.removePrefix("foo")
        }

        fun trimAround(value: CharSequence): String {
            return value.removeSurrounding("foo")
        }

        fun main() {
            val cs: CharSequence = "foofoobarfoo"

            // CharSequence receiver: removePrefix
            println(cs.removePrefix("foo"))

            // CharSequence receiver: removeSuffix
            println(cs.removeSuffix("foo"))

            // CharSequence receiver: removeSurrounding(delimiter)
            println(cs.removeSurrounding("foo"))

            // CharSequence receiver: removeSurrounding(prefix, suffix)
            println(cs.removeSurrounding("foo", "foo"))

            // String argument passed to a CharSequence parameter
            println(trimPrefix("foofoobar"))

            // String argument passed to a CharSequence parameter
            println(trimAround("foofoobarfoo"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextRemovePrefixSuffixCharSequenceEdgeCases",
            expected:
                """
                foobarfoo
                foofoobar
                foobar
                foobar
                foobar
                foobar
                """
                + "\n"
        )
    }

    func testKotlinTextIfBlankEdgeCases() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifBlank { "fallback" }
        }

        fun main() {
            println("[" + "abc".ifBlank { "fallback" } + "]")
            println("[" + "   ".ifBlank { "fallback" } + "]")
            println("[" + "".ifBlank { "empty" } + "]")

            val cs: CharSequence = "   "
            println("[" + choose(cs) + "]")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIfBlankEdgeCases",
            expected:
                """
                [abc]
                [fallback]
                [empty]
                [fallback]
                """
                + "\n"
        )
    }

    func testKotlinTextIfEmptyEdgeCases() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifEmpty { "fallback" }
        }

        fun main() {
            println("[" + "abc".ifEmpty { "fallback" } + "]")
            println("[" + "   ".ifEmpty { "fallback" } + "]")
            println("[" + "".ifEmpty { "empty" } + "]")

            val cs: CharSequence = ""
            println("[" + choose(cs) + "]")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIfEmptyEdgeCases",
            expected:
                """
                [abc]
                [   ]
                [empty]
                [fallback]
                """
                + "\n"
        )
    }

    func testKotlinTextCharSequenceZipWithNextEdgeCases() throws {
        let source = """
        fun pairCount(value: CharSequence): Int {
            return value.zipWithNext().size
        }

        fun labels(value: CharSequence): List<String> {
            return value.zipWithNext { a, b -> "" + a + b }
        }

        fun main() {
            val cs: CharSequence = "abcd"
            val pairs = cs.zipWithNext()
            println(pairs.size)

            val transformed = cs.zipWithNext { a, b -> "" + a + b }
            println(transformed.size)
            println(transformed[0])
            println(transformed[2])

            println(pairCount("xy"))
            println(labels("xy")[0])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCharSequenceZipWithNextEdgeCases",
            expected:
                """
                3
                3
                ab
                cd
                1
                xy
                """
                + "\n"
        )
    }

    func testKotlinTextTakeDropEdgeCases() throws {
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

    func testKotlinTextTakeNegativeThrows() throws {
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

    func testKotlinTextDropNegativeThrows() throws {
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

    func testKotlinTextTakeLastNegativeThrows() throws {
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

    func testKotlinTextDropLastNegativeThrows() throws {
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

    func testKotlinTextCaseConversionEdgeCases() throws {
        let source = """
        fun main() {
            // lowercase
            println("Hello World".lowercase())
            println("".lowercase())
            println("123".lowercase())

            // uppercase
            println("Hello World".uppercase())
            println("".uppercase())

            // lowercase on already-lower
            println("hello".lowercase())

            // uppercase on already-upper
            println("HELLO".uppercase())

            // mixed with digits and symbols
            println("Abc123!".lowercase())
            println("Abc123!".uppercase())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCaseConversionEdgeCases",
            expected:
                """
                hello world

                123
                HELLO WORLD

                hello
                HELLO
                abc123!
                ABC123!
                """
                + "\n"
        )
    }

    func testKotlinTextCaseInsensitiveOrderEdgeCases() throws {
        let source = """
        import kotlin.text.CASE_INSENSITIVE_ORDER

        fun main() {
            println(CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA"))
            println(CASE_INSENSITIVE_ORDER.compare("apple", "banana") < 0)
            println(CASE_INSENSITIVE_ORDER.compare("Zoo", "apple") > 0)
            println(listOf("b", "A", "c", "a").sortedWith(CASE_INSENSITIVE_ORDER))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCaseInsensitiveOrderEdgeCases",
            expected:
                """
                0
                true
                true
                [A, a, b, c]
                """
                + "\n"
        )
    }

    func testKotlinTextCharSequenceZipEdgeCases() throws {
        let source = """
        fun merge(a: String, b: CharSequence): List<String> {
            return a.zip(b) { x, y -> "" + x + y }
        }

        fun main() {
            // String.zip: basic count
            println("abc".zip("xyz").size)

            // Truncation at shorter string
            println("ab".zip("xyz").size)
            println("xyz".zip("ab").size)

            // Empty source returns empty list
            println("".zip("xyz").size)

            // Transform variant
            val joined = "abc".zip("XYZ") { a, b -> "" + a + b }
            println(joined.size)
            println(joined[0])
            println(joined[2])

            // CharSequence receiver
            val cs: CharSequence = "hello"
            println(cs.zip("hi").size)
            val csJoined = cs.zip("HI") { a, b -> "" + a + b }
            println(csJoined[0])
            println(csJoined[1])

            // Via helper function
            println(merge("abc", "123")[1])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCharSequenceZipEdgeCases",
            expected:
                """
                3
                2
                2
                0
                3
                aX
                cZ
                2
                hH
                eI
                b2
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)
    func testKotlinTextToCollectionEdgeCases() throws {
        let source = """
        fun main() {
            val list = mutableListOf<Char>('x')
            val returnedList: MutableList<Char> = "ab".toCollection(list)
            println(returnedList)
            println(list)
            println(returnedList.size)

            val cs: CharSequence = "cda"
            val set = mutableSetOf<Char>('c')
            val returnedSet: MutableSet<Char> = cs.toCollection(set)
            println(returnedSet)
            println(returnedSet.size)

            val empty = mutableListOf<Char>('q')
            println("".toCollection(empty))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextToCollectionEdgeCases",
            expected:
                """
                [x, a, b]
                [x, a, b]
                3
                [c, d, a]
                3
                [q]
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-108: CharSequence.toSortedSet(): SortedSet<Char>
    // End-to-end execution coverage — the runtime/Sema layers are tested in
    // isolation elsewhere; this asserts the full compile-and-run pipeline
    // produces a sorted, deduplicated set that honours the `Set` surface.
    func testKotlinTextToSortedSetEdgeCases() throws {
        let source = """
        fun main() {
            // Basic: sorted ascending and deduplicated ('l' appears twice).
            val h = "hello".toSortedSet()
            println(h)
            println(h.size)

            // Reverse-ordered input is sorted into ascending order.
            println("cba".toSortedSet())

            // The result honours the Set surface (membership queries).
            println(h.contains('l'))
            println(h.contains('z'))

            // Ordering follows the natural Char (UTF-16 code unit) order, so
            // digits precede letters.
            println("b3a1".toSortedSet())

            // CharSequence receiver resolves to the same extension.
            val cs: CharSequence = "banana"
            val b: Set<Char> = cs.toSortedSet()
            println(b)
            println(b.size)

            // Empty input yields an empty set.
            val e = "".toSortedSet()
            println(e)
            println(e.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextToSortedSetEdgeCases",
            expected:
                """
                [e, h, l, o]
                4
                [a, b, c]
                true
                false
                [1, 3, a, b]
                [a, b, n]
                3
                []
                0
                """
                + "\n"
        )
    }
}

