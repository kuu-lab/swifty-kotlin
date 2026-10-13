import Foundation
import Testing

extension BundledStdlibExecutionTests {
    /// Keep each JVM-reference fixture in its own package, then compile the
    /// matrix together to amortize source-injection stdlib compilation.
    @Test(arguments: [true, false])
    func testKotlinTestBasicAssertions(allowDefaultStdlibLibrary: Bool) throws {
        let cases = ["true", "false", "equals", "not_equals", "identity", "null", "fail", "expect", "todo"]
        var sources: [String] = []
        var expected = ""
        for name in cases {
            let caseName = "kotlin_test_" + name
            var source = try diffCaseSource(caseName + ".kt", file: #filePath)
                .replacingOccurrences(of: "fun main()", with: "fun runCase()")
            // File annotations precede package declarations in Kotlin.
            let importIndex = try #require(source.range(of: "import kotlin.test.*")?.lowerBound)
            source.insert(contentsOf: "package fixture_" + name + "\n", at: importIndex)
            sources.append(source)
            expected += try diffCaseSource(caseName + ".expected", file: #filePath)
        }
        sources.append("fun main() {\n" + cases.map { "fixture_" + $0 + ".runCase()" }.joined(separator: "\n") + "\n}")
        try compileAndRunKotlinSources(
            sources,
            expectedOutput: expected,
            moduleName: "KotlinTestBasicAssertions",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKotlinTestBasicAssertionsLazyMessages(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("kotlin_test_lazy_messages.kt", file: #filePath),
            expectedOutput: diffCaseSource("kotlin_test_lazy_messages.expected", file: #filePath),
            moduleName: "KotlinTestBasicAssertionsLazyMessages",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
