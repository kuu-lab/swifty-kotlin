#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DoubleElseParsingTests {
    private func parse(_ source: String) -> DiagnosticEngine {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()
        return lexed.diagnostics
    }

    @Test(arguments: [
        "if (a) 1 else 2 else 3",
        "if (a) { } else { } else { }",
        "if (a) 1 else 2; else 3",
        "if (a) if (b) 1 else 2 else 3 else 4",
    ])
    func rejectsSecondElseBranch(_ source: String) throws {
        let diagnostics = parse(source)
        let diagnostic = try #require(diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0018" && $0.message == "Unexpected 'else' after if expression."
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "if (a) 1 else 2",
        "if (a) { } else { }",
        "if (a) 1 else if (b) 2 else 3",
        "if (a) if (b) 1 else 2 else 3",
        "if (a) { if (b) 1 else 2 } else 3",
    ])
    func acceptsSingleElseAndElseIfChains(_ source: String) {
        let diagnostics = parse(source)
        #expect(diagnostics.diagnostics.isEmpty)
    }
}
#endif
