#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AssignmentInControlFlowConditionTests {
    @Test(arguments: [
        "if (x = 5) true else false",
        "if (x += 5) true else false",
        "while (x = 5) {}",
        "do {} while (x = 5)",
    ])
    func rejectsAssignmentInCondition(_ source: String) throws {
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
        let assignmentOperatorStart = try #require(source.firstIndex {
            "=+-*/%".contains($0)
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Unexpected token after expression.")
        #expect(diagnostic.primaryRange?.start.offset == source[..<assignmentOperatorStart].utf8.count)
    }

    @Test(arguments: [
        "if (x == 5) true else false",
        "while (x < 5) {}",
        "do {} while (x < 5)",
    ])
    func acceptsComparisonInCondition(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
    }
}
#endif
