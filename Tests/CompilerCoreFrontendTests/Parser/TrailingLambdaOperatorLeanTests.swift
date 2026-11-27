#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("in values", true),
        ("!in values", true),
        ("!is Type", true),
        ("!\nis Type", true),
        ("!!", true),
        ("and 1", true),
        ("`and` \"value\"", true),
        ("and field", true),
        ("and private", true),
        ("and -value", true),
        ("and ::target", true),
        ("and\n1", true),
        ("! value", false),
        ("! `in`", false),
        ("is Type", false),
        ("get value", false),
        ("and fun () {}", false),
        ("and +=", false),
        ("and", false),
        ("\nin values", false),
        ("\n!is Type", false),
        ("\n!!", false),
        ("\nand 1", false),
    ])
    func trailingLambdaOperatorContinuationContracts(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(LeanParser.continuesAfterBlock(parser, sawTry: false) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif
