#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ControlFlowParenthesisRequirementTests {
    private func parse(_ source: String) -> (expr: ExprID?, diagnostics: DiagnosticEngine) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        return (parser.parse(), lexed.diagnostics)
    }

    @Test(arguments: [
        ("if x > 5 { }", "Expected parenthesized condition after 'if'."),
        ("while x < 5 { }", "Expected parenthesized condition after 'while'."),
        ("for x in 1..5 { }", "Expected parenthesized loop header after 'for'."),
        ("do { } while x < 5", "Expected parenthesized condition after 'while'."),
        ("loop@ while x < 5 { }", "Expected parenthesized condition after 'while'."),
        ("loop@ for x in 1..5 { }", "Expected parenthesized loop header after 'for'."),
    ])
    func rejectsMissingOpeningParenthesis(_ source: String, _ message: String) throws {
        let result = parse(source)
        let diagnostic = try #require(result.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0004" && $0.message == message
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        ("do { }", "Expected 'while' after 'do' block."),
        ("for (x) { }", "Expected 'in' in 'for' loop header."),
        ("for (x in) { }", "Expected expression."),
        ("if (x > 5) { } else", "Expected branch after 'else'."),
        ("while (x < 5", "Expected ')' after 'while' condition."),
        ("for (x in 1..5", "Expected ')' after 'for' loop header."),
        ("if (x > 5", "Expected ')' after 'if' condition."),
    ])
    func rejectsOtherMalformedControlFlow(_ source: String, _ message: String) throws {
        let result = parse(source)
        let diagnostic = try #require(result.diagnostics.diagnostics.first {
            $0.message == message
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "if (x > 5) { } else { }",
        "while (x < 5) { }",
        "for (x in 1..5) { }",
        "for ((a, b) in pairs) { }",
        "do { } while (x < 5)",
        "while (x < 5);",
        "if (x > 5) 1 else 2",
        "if (x > 5) { } else if (x > 1) { }",
    ])
    func acceptsWellFormedControlFlow(_ source: String) throws {
        let result = parse(source)
        #expect(result.expr != nil)
        #expect(result.diagnostics.diagnostics.isEmpty)
    }
}
#endif
