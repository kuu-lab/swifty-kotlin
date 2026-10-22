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
        "when (x = 5) {}",
        "when (x += 5) {}",
        "when (x -= 5) {}",
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
        "when (val y) {}",
        "when (x)",
        "when",
    ])
    func rejectsMalformedWhenHeader(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0010"
        })
    }

    @Test(arguments: [
        "when (val (a, b) = p) {}",
        "when (= 1) {}",
    ])
    func rejectsNonExpressionWhenSubject(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0001"
        })
    }

    @Test(arguments: [
        "when (val y = (x = 1)) {}",
        "when (val y = x = 1) {}",
    ])
    func rejectsAssignmentInWhenSubjectVariableInitializer(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0018"
        })
    }

    @Test(arguments: [
        "if (x == 5) true else false",
        "while (x < 5) {}",
        "do {} while (x < 5)",
        "when (x) {}",
        "when (x == 5) {}",
        "when (val y = x) {}",
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
