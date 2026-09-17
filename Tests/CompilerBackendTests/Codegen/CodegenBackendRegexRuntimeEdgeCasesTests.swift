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

            println(Regex("a").toString())
            println(Regex("a").pattern)

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
                a
                a
                3
                -a-b-
                05/2024
                05/2024
                """
                + "\n"
        )
    }
}
#endif
