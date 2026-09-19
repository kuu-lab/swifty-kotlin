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
}
#endif
