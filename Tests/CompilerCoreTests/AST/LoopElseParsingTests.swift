#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LoopElseParsingTests {
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
        "while (a) f() else g()",
        "while (a) { } else { }",
        "while (a) f(); else g()",
        "for (i in xs) f() else g()",
        "do { } while (a) else g()",
    ])
    func rejectsElseAfterLoop(_ source: String) throws {
        let diagnostics = parse(source)
        let diagnostic = try #require(diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0018" && $0.message == "Unexpected 'else' after if expression."
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "while (a) f()",
        "while (a) if (b) 1 else 2",
        "for (i in xs) f()",
        "do { } while (a)",
        "if (a) while (b) f() else g()",
        "if (a) for (i in xs) f() else g()",
        "if (a) do { } while (b) else g()",
    ])
    func acceptsLoopsAndDanglingElseBinding(_ source: String) {
        let diagnostics = parse(source)
        #expect(diagnostics.diagnostics.isEmpty)
    }
}
#endif
