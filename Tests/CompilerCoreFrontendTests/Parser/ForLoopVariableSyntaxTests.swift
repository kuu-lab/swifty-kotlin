#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ForLoopVariableSyntaxTests {
    @Test(arguments: ["var", "val"])
    func declarationModifiersAreRejected(modifier: String) throws {
        let source = "fun main() { for (\(modifier) i in 1..3) {} }"
        let parsed = parse(source)
        let diagnostic = try #require(parsed.diagnostics.diagnostics.first)

        #expect(parsed.diagnostics.diagnostics.count == 1)
        #expect(diagnostic.code == "KSWIFTK-PARSE-0021")
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "A for-loop variable cannot be declared with 'val' or 'var'.")
        let range = try #require(diagnostic.primaryRange)
        #expect(String(decoding: Array(source.utf8)[range.start.offset ..< range.end.offset], as: UTF8.self) == modifier)
    }

    @Test(arguments: [
        "for (i in 1..3) {}",
        "for (i: Int in 1..3) {}",
    ])
    func implicitAndTypedLoopVariablesRemainValid(loop: String) {
        let parsed = parse("fun main() { \(loop) }")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
