#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct MissingInfixOperandParsingTests {
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
        "1 as",
        "1 as )",
        "1 as? )",
        "x as + y",
    ])
    func rejectsMissingAsCastType(_ source: String) throws {
        let diagnostics = parse(source)
        let diagnostic = try #require(diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0005" && $0.message == "Expected type after 'as'."
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "1 is",
        "1 is )",
        "1 !is )",
    ])
    func rejectsMissingIsCheckType(_ source: String) throws {
        let diagnostics = parse(source)
        let diagnostic = try #require(diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0005" && $0.message == "Expected type after 'is'."
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "1 in",
        "1 !in )",
        "x in ,",
    ])
    func rejectsMissingInOperand(_ source: String) throws {
        let diagnostics = parse(source)
        let diagnostic = try #require(diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0001" && $0.message == "Expected expression after 'in'."
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "1 as Int",
        "1 as? Int",
        "1 is Int",
        "x !is String",
        "x in 1..5",
        "x !in list",
    ])
    func acceptsCompleteInfixOperands(_ source: String) {
        let diagnostics = parse(source)
        #expect(diagnostics.diagnostics.isEmpty)
    }
}
#endif
