#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendKotlinTextReplaceEdgeCasesTests {

    @Test func testKotlinTextReplaceEdgeCases() throws {
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

            // replace with empty old value inserts the replacement at the boundary
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
                x
                Zabaa
                hello

                """
                + "\n"
        )
    }

    @Test func testKotlinTextReplaceRangeEdgeCases() throws {
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

    @Test func testKotlinTextReplaceAfterEdgeCases() throws {
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

    @Test func testKotlinTextReplaceAfterLastEdgeCases() throws {
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

    @Test func testKotlinTextReplaceBeforeEdgeCases() throws {
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

    @Test func testKotlinTextReplaceBeforeLastEdgeCases() throws {
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

    @Test func testKotlinTextReplaceIndentByMarginEdgeCases() throws {
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
            try {
                marker("|line".replaceIndentByMargin(">", "   "))
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
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
                marginPrefix must be non-blank string.
                """
                + "\n"
        )
    }

    @Test func testKotlinTextRemovePrefixSuffixEdgeCases() throws {
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

    @Test func testKotlinTextRemovePrefixSuffixCharSequenceEdgeCases() throws {
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
}
#endif
