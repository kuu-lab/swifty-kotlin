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

    @Test
    func testCodegenRegexReplaceLambdaPassesMatchResult() throws {
        let source = """
        fun main() {
            val regex = Regex("(\\\\d+)-(\\\\d+)")
            println(regex.replace("1-2 3-4") { it.groupValues[1] + "+" + it.groupValues[2] })
            println(regex.replace("1-2 3-4") { "X" })
            println(Regex("\\\\w+").replace("hello world") { it.value.uppercase() })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexReplaceLambda",
            expected: "1+2 3+4\nX X\nHELLO WORLD\n"
        )
    }
}
#endif
