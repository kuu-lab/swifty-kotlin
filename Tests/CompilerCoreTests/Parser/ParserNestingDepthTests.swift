#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ParserNestingDepthTests {
    @Test("Structured syntax at the shared nesting limit parses")
    func structuredSyntaxAtLimitParses() {
        let source = String(repeating: "if (true) ", count: KotlinParser.maxNestingDepth - 1) + "1"
        let parsed = parse(source)

        #expect(!parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0013" })
    }

    @Test("Excess structured nesting reports once and resumes at the next declaration")
    func excessStructuredNestingReportsOnceAndResumes() {
        let deepIf = String(repeating: "if (true) ", count: KotlinParser.maxNestingDepth + 16) + "1"
        let parsed = parse(deepIf + "\nfun afterDepthLimit() = 1\n")

        let depthDiagnostics = parsed.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PARSE-0013" }
        let functionCount = parsed.arena.nodes.filter { $0.kind == .funDecl }.count

        #expect(depthDiagnostics.count == 1)
        #expect(functionCount == 1)
    }
}
#endif
