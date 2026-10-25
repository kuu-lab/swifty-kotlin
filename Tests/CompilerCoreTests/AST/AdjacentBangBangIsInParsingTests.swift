#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AdjacentBangBangIsInParsingTests {
    // Kotlin treats the second `!` as the start of `!is`/`!in` when there is
    // no trivia, so the parser must not accept the sequence as `!!` + operator.
    @Test(arguments: [
        "5 !!is Int",
        "5 !!in listOf(5)",
    ])
    func rejectsBangBangAdjacentToNegatedOperator(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0018" && $0.severity == .error
        }, "Expected KSWIFTK-PARSE-0018 for \(source), got: \(lexed.diagnostics.diagnostics.map(\.message))")
    }

    @Test(arguments: [
        "5!! is Int",
        "5 !! is Int",
        "5!! in listOf(5)",
        "5 !! in listOf(5)",
    ])
    func acceptsNullAssertionSeparatedFromNegatedOperator(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty,
                "Expected no diagnostics for \(source), got: \(lexed.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func doesNotSplitNullAssertionBeforeLongerIdentifier() {
        let lexed = lex("5!!island")

        #expect(lexed.tokens.map(\.kind) == [
            .intLiteral("5"),
            .symbol(.bangBang),
            .identifier(lexed.interner.intern("island")),
            .eof,
        ])
    }
}
#endif
