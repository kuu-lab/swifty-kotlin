import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKotlinTestAssertionFamilies(allowDefaultStdlibLibrary: Bool) throws {
        let cases = ["types", "failures", "contains", "content", "tolerance", "callable_helpers"]
        var sources: [String] = []
        var expected = ""
        for name in cases {
            let caseName = "kotlin_test_" + name
            var source = try diffCaseSource(caseName + ".kt", file: #filePath)
                .replacingOccurrences(of: "fun main()", with: "fun runCase()")
            let importIndex = try #require(source.range(of: "import kotlin.test.*")?.lowerBound)
            source.insert(contentsOf: "package family_" + name + "\n", at: importIndex)
            sources.append(source)
            expected += try diffCaseSource(caseName + ".expected", file: #filePath)
        }
        sources.append("fun main() {\n" + cases.map { "family_" + $0 + ".runCase()" }.joined(separator: "\n") + "\n}")
        try compileAndRunKotlinSources(
            sources, expectedOutput: expected, moduleName: "KotlinTestAssertionFamilies",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKotlinTestAssertionFamiliesLazyMessages(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("kotlin_test_families_lazy.kt", file: #filePath),
            expectedOutput: diffCaseSource("kotlin_test_families_lazy.expected", file: #filePath),
            moduleName: "KotlinTestAssertionFamiliesLazyMessages",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
