#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct QuestionMarkExpressionParsingTests {
    @Test(arguments: [
        "y ?",
        "y ?= 1",
        "y ? = 1",
        "f() ? g()",
        "1 ? 2",
    ])
    func rejectsBareQuestionMarkAfterExpression(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0018"
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Unexpected token after expression.")
    }

    @Test(arguments: [
        "? = 1",
        "? 1",
    ])
    func rejectsLeadingQuestionMark(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() == nil)
        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0001"
        })
        #expect(diagnostic.severity == .error)
    }

    @Test(arguments: [
        "a ?: b",
        "x?.y",
        "x?.y?.z",
        "a as? Int",
        "a is Int?",
        "x ?: y ?: z",
        "f(x) ?: g(y)",
    ])
    func acceptsLegalQuestionMarkForms(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
