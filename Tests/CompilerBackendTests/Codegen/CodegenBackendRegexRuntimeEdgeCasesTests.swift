#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRegexRuntimeEdgeCasesTests {

    @Test
    func testCodegenCompilesRegexRuntimeEdgeCases() throws {
        let source = """
        fun main() {
            val named = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            val match = named.find("2025-04")
            println(match?.groups?.get("year")?.value)
            println(match?.groups?.get("month")?.value)

            try {
                Regex("(")
                println("unexpected-regex")
            } catch (e: Throwable) {
                println("invalid-pattern")
            }

            val empty = Regex("")
            println(empty.findAll("ab").count())
            println(empty.replace("ab", "-"))

            val namedReplace = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            println(namedReplace.replace("2024-05", "$2/$1"))
            println(namedReplace.replace("2024-05", "\\${month}/\\${year}"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexRuntimeEdgeCases",
            expected:
                """
                2025
                04
                invalid-pattern
                3
                -a-b-
                05/2024
                05/2024
                """
                + "\n"
        )
    }

    @Test
    func testRegexReplacementTemplateThrowsForInvalidGroupReferences() throws {
        let source = """
        fun main() {
            try {
                Regex("a").replace("a", "\\$1")
                println("unexpected-replace-index")
            } catch (e: IndexOutOfBoundsException) {
                println("replace-index")
            }

            try {
                Regex("a").replace("a", "\\$x")
                println("unexpected-replace-dollar")
            } catch (e: IllegalArgumentException) {
                println("replace-dollar")
            }

            try {
                Regex("a").replace("a", "\\$")
                println("unexpected-replace-missing")
            } catch (e: IllegalArgumentException) {
                println("replace-missing")
            }

            try {
                Regex("a").replaceFirst("a", "\\$1")
                println("unexpected-first-index")
            } catch (e: IndexOutOfBoundsException) {
                println("first-index")
            }

            try {
                Regex("(?<value>a)").replaceFirst("a", "\\${missing}")
                println("unexpected-first-name")
            } catch (e: IllegalArgumentException) {
                println("first-name")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexReplacementTemplateErrors",
            expected: "replace-index\nreplace-dollar\nreplace-missing\nfirst-index\nfirst-name\n"
        )
    }
}
#endif
