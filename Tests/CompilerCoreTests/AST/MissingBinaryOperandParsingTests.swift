#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MissingBinaryOperandParsingTests {
    @Test
    func rejectsMissingRightOperandBeforeClosingBrace() throws {
        let (_, context) = try buildASTModule(
            from: "fun main() { val x = 1 + }",
            includeStdlib: false
        )

        let diagnostic = try #require(context.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0001"
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected expression.")
    }

    @Test(arguments: [
        "1 +",
        "1 -",
        "1 *",
        "1 /",
        "1 %",
        "1 ..",
        "1 ..<",
        "1 step",
        "1 downTo",
        "1 downTo 0 step",
        "1 == ",
        "1 === ",
        "a &&",
        "a ||",
        "a ?:",
        "1 <",
        "1 <=",
        "1 >",
        "1 >=",
        "1 !=",
        "1 !==",
    ])
    func rejectsBinaryOperatorWithoutRightOperand(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0001"
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected expression.")
    }

    @Test(arguments: [
        "1 + 2",
        "1 - 2",
        "1 * 2 / 3 % 4",
        "1 .. 5",
        "1 ..< 5",
        "1..5 step 2",
        "10 downTo 0",
        "10 downTo 0 step 3",
        "a ?: 0",
        "a ?: 0 ?: 5",
        "a && b",
        "a || b && c",
        "1 == 2",
        "1 === 2",
        "1 != 2",
        "1 !== 2",
        "1 < 2",
        "1 <= 2",
        "1 > 2",
        "1 >= 2",
        "1 + 2 * 3 - 4",
        "-a + +b",
    ])
    func acceptsCompleteBinaryExpressions(_ source: String) throws {
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
