#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrefixBangBangParsingTests {
    @Test(arguments: ["!!true", "!(!true)", "! !true", "!false"])
    func parsesPrefixNotForms(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func adjacentPrefixNotIsTwoUnaryOperators() throws {
        let lexed = lex("!!true")
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )

        let expression = try #require(parser.parse())
        guard case let .unaryExpr(.not, inner, outerRange) = arena.expr(expression),
              case let .unaryExpr(.not, operand, innerRange) = arena.expr(inner),
              case let .boolLiteral(value, operandRange) = arena.expr(operand)
        else {
            Issue.record("Expected adjacent prefix `!!` to produce two unary-not expressions")
            return
        }

        #expect(value)
        #expect(outerRange.start.offset == 0)
        #expect(outerRange.end.offset == 6)
        #expect(innerRange.start.offset == 1)
        #expect(innerRange.end.offset == 6)
        #expect(operandRange.start.offset == 2)
        #expect(operandRange.end.offset == 6)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func postfixBangBangRemainsNullAssertion() throws {
        let lexed = lex("value!!")
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )

        let expression = try #require(parser.parse())
        guard case let .nullAssert(operand, range) = arena.expr(expression),
              case let .nameRef(name, _) = arena.expr(operand)
        else {
            Issue.record("Expected postfix `!!` to remain a null assertion")
            return
        }

        #expect(name == lexed.interner.intern("value"))
        #expect(range.start.offset == 0)
        #expect(range.end.offset == 7)
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
