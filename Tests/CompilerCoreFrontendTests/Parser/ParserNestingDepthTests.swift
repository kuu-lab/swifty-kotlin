#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ParserNestingDepthTests {
    @Test("Structured syntax at the shared nesting limit parses")
    func structuredSyntaxAtLimitParses() {
        let source = String(repeating: "if (true) ", count: KotlinParser.maxNestingDepth - 1) + "1"
        let parsed = parse(source)

        #expect(!parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0013" })
    }

    @Test(arguments: [
        ("", false, 0),
        ("", true, 0),
        (";", true, 1),
        ("; next", true, 1),
        ("} next", true, 1),
        ("val next", false, 1),
        ("\nnext val value", true, 1),
        ("junk\nnext", true, 1),
        ("junk\nnext", false, 2),
        ("junk } next", true, 1),
        ("junk catch next", true, 1),
        ("} junk val next", false, 2),
    ])
    func nestingLimitRecoveryStopsAtExpectedToken(source: String, inBlock: Bool, skipped: Int) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let node = parser.recoverFromNestingLimit(inBlock: inBlock, kind: .block)

        #expect(parser.stream.index == skipped)
        #expect(parser.stream.peek() == lexed.tokens[skipped])
        #expect(parser.arena.node(node).kind == .block)
        #expect(parser.arena.children(of: node).count == skipped)
        #expect(lexed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0013"])
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
