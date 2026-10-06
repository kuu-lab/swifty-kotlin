#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRegexEdgeCasesTests {

    @Test
    func testCodegenCompilesRegexEdgeCases() throws {
        let source = """
        fun main() {
            val regex = Regex("[a-z]+")
            println(regex.containsMatchIn("123abc"))
            println(regex.matchEntire("abc")?.value)
            println(regex.matchEntire("abc123"))

            println("a b   c".replace(Regex("\\\\s+"), "-"))
            println("one1two2three".split(Regex("[0-9]+")))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexEdgeCases",
            expected:
                """
                true
                abc
                null
                a-b-c
                [one, two, three]
                """
                + "\n"
        )
    }

    // KUU-635: Regex.split(input, limit) adds the pre-match segment (possibly
    // empty) for zero-width matches and rejects negative limits.
    @Test
    func testCodegenRegexSplitWithLimitZeroWidthAndNegativeLimit() throws {
        let source = """
        fun main() {
            println("abc".split(Regex("x*"), 3))
            println("a1b".split(Regex("\\\\d*"), 5))
            println("abc".split(Regex(""), 3))
            println("axbxc".split(Regex("x*"), 4))
            println("".split(Regex("x*"), 3))
            println("abc".split(Regex("x*"), 2))
            println("a,b,c".split(Regex(","), 2))
            println("abc".split(Regex("b"), 1))

            try {
                "ab".split(Regex("b"), -1)
                println("no-throw")
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                println(Regex("b").splitToSequence("ab", -1).toList())
                println("no-throw2")
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexSplitLimitZeroWidth",
            expected:
                """
                [, a, bc]
                [, a, , b, ]
                [, a, bc]
                [, a, , bxc]
                [, ]
                [, abc]
                [a, b,c]
                [abc]
                Limit must be non-negative, but was -1
                Limit must be non-negative, but was -1
                """
                + "\n"
        )
    }

    @Test(arguments: [true, false])
    func testCodegenRegexReplaceLambdaPassesMatchResult(useArtifact: Bool) throws {
        let source = """
        fun main() {
            println(Regex("a").replace("aaa") { "X" })
            println(Regex("a").replace("aaa") { it.value + "!" })
            val regex = Regex("(\\\\d+)-(\\\\d+)")
            println(regex.replace("1-2 3-4") { it.groupValues[1] + "+" + it.groupValues[2] })
            println(regex.replace("1-2 3-4") { "X" })
            println(Regex("\\\\w+").replace("hello world") { it.value.uppercase() })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexReplaceLambda",
            expected: "XXX\na!a!a!\n1+2 3+4\nX X\nHELLO WORLD\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test
    func testCodegenRegexReplaceTransformEdgeCases() throws {
        let source = #"""
        fun main() {
            var calls = 0
            println(Regex("a").replace("bbb") { calls++; "X" })
            println(Regex("a").replace("") { calls++; "X" })
            println(calls)
            println(Regex("").replace("ab") { "|" })
            println(Regex("").replace("") { "|" })
            println(Regex("a").replace("banana") { "" })
            println(Regex("(a)").replace("aba") { "\$1\\literal" })

            var index = 0
            println(Regex("a").replace("aaa") { index++; it.value + index })
            println(index)
            try {
                Regex("a").replace("aaa") { throw IllegalStateException("transform failed") }
                println("no-throw")
            } catch (e: IllegalStateException) {
                println(e.message)
            }
        }
        """#

        try assertKotlinOutput(
            source,
            moduleName: "RegexReplaceTransformEdgeCases",
            expected: "bbb\n\n0\n|a|b|\n|\nbnn\n$1\\literalb$1\\literal\na1a2a3\n3\ntransform failed\n"
        )
    }

    @Test
    func testCodegenRegexKuu770UsesKotlinCompatibleSignatures() throws {
        let source = """
        fun main() {
            val regex = Regex("b")
            val matches: Sequence<MatchResult> = regex.findAll("abcb")
            println(matches.map { it.range.first }.toList())
            println(regex.findAll("abcb", 2).map { it.range.first }.toList())
            println(regex.find("abcb", 2)?.range)
            println(regex.matchAt("abcb", 1)?.value)
            println(regex.matchesAt("abcb", 1))
            println(regex.replace("abcb") { it.value as CharSequence })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexKuu770Signatures",
            expected: "[1, 3]\n[3]\n3..3\nb\ntrue\nabcb\n"
        )
    }

    @Test
    func testCodegenMatchResultNextKeepsOriginalInputContext() throws {
        let source = """
        fun show(match: MatchResult?) {
            if (match == null) {
                println("null")
            } else {
                println(match.value + ":" + match.range.first + ":" + match.range.last)
            }
        }

        fun main() {
            show(Regex("^.").find("ab")!!.next())
            show(Regex("\\\\b\\\\w").find("ab")!!.next())
            show(Regex("(?<=^).").find("ab")!!.next())
            show(Regex("a|(?<=a)b").find("ab")!!.next())
            show(Regex("\\\\d+").find("a1b22")!!.next())
            show(Regex("b|$").find("ab")!!.next())
            show(Regex("^.").find("ab", 1))
            show(Regex("^.", RegexOption.MULTILINE).find("ab\\ncd")!!.next())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchResultNextContext",
            expected:
                """
                null
                null
                null
                b:1:1
                22:3:4
                :2:1
                null
                c:3:3
                """
                + "\n"
        )
    }

    @Test
    func testRegexFindAndFindAllStartIndexOverloads() throws {
        let source = """
        fun main() {
            println(Regex("b").find("abc", 2))
            println(Regex("a").findAll("aaa", 1).count())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexFindStartIndexOverloads",
            expected: "null\n2\n"
        )
    }
}
#endif
