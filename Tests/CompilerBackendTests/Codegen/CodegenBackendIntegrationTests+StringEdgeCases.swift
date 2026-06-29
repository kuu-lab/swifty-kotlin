@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesStringEdgeCases() throws {
        let source = """
        fun dumpLines(prefix: String, values: List<String>) {
            println("$prefix:${values.joinToString("|")}")
        }

        fun main() {
            println("hello".substringBefore("."))
            println("hello.world.kt".substringBefore("."))
            println("hello.world.kt".substringBeforeLast("."))
            println("nodelem".substringBefore(":"))

            println("hello".replaceFirstChar { 'H' })
            println("beta".replaceFirstChar { 'B' })
            println("".replaceFirstChar { 'X' })

            dumpLines("lines-empty", "".lines())
            dumpLines("lines-ascii", "a\nb\n".lines())
            dumpLines("lines-unicode", "こんにちは\n世界".lines())

            dumpLines("seq-empty", "".lineSequence().toList())
            dumpLines("seq-mixed", "a\r\nb\nc".lineSequence().toList())
            dumpLines("seq-head-tail", "\nalpha\n".lineSequence().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringEdgeCases",
            expected:
                """
                hello
                hello
                hello.world
                nodelem
                Hello
                Beta

                lines-empty:
                lines-ascii:a|b|
                lines-unicode:こんにちは|世界
                seq-empty:
                seq-mixed:a|b|c
                seq-head-tail:|alpha|
                """
                + "\n"
        )
    }

    func testCodegenCompilesSubstringAfterLastEdgeCases() throws {
        let source = """
        fun main() {
            // String delimiter — keep the segment after the last delimiter.
            println("path/to/file.txt".substringAfterLast("/"))
            println("a.b.c".substringAfterLast("."))
            // Char delimiter overload.
            println("path/to/file.txt".substringAfterLast('/'))
            println("a.b.c".substringAfterLast('.'))
            // No delimiter present — default missingDelimiterValue is the receiver.
            println("nodelimiter".substringAfterLast("."))
            println("nodelimiter".substringAfterLast('.'))
            // No delimiter present — explicit fallback wins.
            println("nodelimiter".substringAfterLast(".", "<none>"))
            println("nodelimiter".substringAfterLast('.', "<none>"))
            // Multi-scalar delimiter: start = lastIndex + delimiter.length.
            println("a::b::c".substringAfterLast("::"))
            // Unicode receiver/delimiter resolve on scalar boundaries.
            println("こんにちは。世界".substringAfterLast("。"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SubstringAfterLastEdgeCases",
            expected:
                """
                file.txt
                c
                file.txt
                c
                nodelimiter
                nodelimiter
                <none>
                <none>
                c
                世界
                """
                + "\n"
        )
    }

    func testCodegenCompilesSubstringAfterEdgeCases() throws {
        let source = """
        fun main() {
            // String delimiter — keep the segment after the first delimiter.
            println("path/to/file.txt".substringAfter("/"))
            println("a.b.c".substringAfter("."))
            // Char delimiter overload.
            println("path/to/file.txt".substringAfter('/'))
            println("a.b.c".substringAfter('.'))
            // No delimiter present — default missingDelimiterValue is the receiver.
            println("nodelimiter".substringAfter("."))
            println("nodelimiter".substringAfter('.'))
            // No delimiter present — explicit fallback wins.
            println("nodelimiter".substringAfter(".", "<none>"))
            println("nodelimiter".substringAfter('.', "<none>"))
            // Multi-scalar delimiter: slice resumes past the whole first match.
            println("a::b::c".substringAfter("::"))
            // Unicode receiver/delimiter resolve on scalar boundaries.
            println("こんにちは。世界".substringAfter("。"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SubstringAfterEdgeCases",
            expected:
                """
                to/file.txt
                b.c
                to/file.txt
                b.c
                nodelimiter
                nodelimiter
                <none>
                <none>
                b::c
                世界
                """
                + "\n"
        )
    }

    func testCodegenCompilesStringContentEqualsEdgeCases() throws {
        let source = """
        fun main() {
            val a: String? = "hello"
            val b: String? = "hello"
            val c: String? = "HELLO"
            val d: String? = null
            val e: String? = null

            // Basic contentEquals
            println(a.contentEquals(b))
            println(a.contentEquals(c))
            println(a.contentEquals(d))
            println(d.contentEquals(e))

            // contentEquals with ignoreCase
            println(a.contentEquals(c, true))
            println(a.contentEquals(c, false))
            println(d.contentEquals(e, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringContentEqualsEdgeCases",
            expected:
                """
                true
                false
                false
                true
                true
                false
                true
                """
                + "\n"
        )
    }

    func testCodegenNumberFormatExceptionIsCaught() throws {
        let source = """
        fun main() {
            try {
                val n = "xyz".toInt()
                println("unexpected: $n")
            } catch (e: NumberFormatException) {
                println("caught-nfe")
            }

            try {
                val n = "abc".toLong()
                println("unexpected: $n")
            } catch (e: NumberFormatException) {
                println("caught-nfe-long")
            }

            try {
                val n = "bad".toDouble()
                println("unexpected: $n")
            } catch (e: NumberFormatException) {
                println("caught-nfe-double")
            }

            try {
                val n = "xyz".toInt()
                println("unexpected: $n")
            } catch (e: IllegalArgumentException) {
                println("caught-iae")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NumberFormatExceptionCatch",
            expected:
                """
                caught-nfe
                caught-nfe-long
                caught-nfe-double
                caught-iae
                """
                + "\n"
        )
    }
}

