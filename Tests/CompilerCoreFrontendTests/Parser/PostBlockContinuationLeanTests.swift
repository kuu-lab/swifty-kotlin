#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("+ value", false, true),
        ("- value", false, true),
        ("\n+ value", false, false),
        ("\n- value", false, false),
        ("(value)", false, true),
        ("\n(value)", false, false),
        ("\n?.member", false, true),
        ("\n?: fallback", false, true),
        ("\n*= value", false, true),
        ("\nby value", false, true),
        ("\nas Type", false, true),
        ("\nelse {}", false, true),
        ("\ncatch (e: E) {}", true, true),
        ("catch (e: E) {}", false, false),
        ("finally {}", true, true),
        ("\nfinally {}", false, false),
        ("\n< value", false, false),
        ("++;", false, false),
        (";", false, false),
        ("", false, false),
    ])
    func postBlockContinuationContracts(source: String, sawTry: Bool, continues: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(LeanParser.continuesAfterBlock(parser, sawTry: sawTry) == continues)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif
