#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func isLinux() -> Bool {
#if os(Linux)
    return true
#else
    return false
#endif
}

@Suite
struct CodegenBackendRegexOptionEdgeCasesTests {

    @Test(
        .disabled(if: isLinux(), "Regex option edge cases test temporarily disabled on Linux")
    )
    func testCodegenCompilesRegexOptionEdgeCases() throws {
        let source = """
        fun main() {
            val ignoreCase = Regex("hello", RegexOption.IGNORE_CASE)
            println(ignoreCase.containsMatchIn("HeLLo"))

            val dotDefault = Regex("a.b")
            val dotAll = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
            println(dotDefault.containsMatchIn("a\\nb"))
            println(dotAll.containsMatchIn("a\\nb"))

            val combined = Regex(
                "^hello.world$",
                setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL, RegexOption.MULTILINE)
            )
            println(combined.containsMatchIn("HELLO\\nWORLD"))
            println(combined.matchEntire("hello\\nworld")?.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexOptionEdgeCases",
            expected:
                """
                true
                false
                true
                true
                hello
                world
                """ + "\n"
        )
    }
}
#endif
