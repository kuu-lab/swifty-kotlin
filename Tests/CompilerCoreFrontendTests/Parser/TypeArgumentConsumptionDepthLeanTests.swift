#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func deeplyNestedTypeArgumentConsumptionKeepsFollowingToken() {
        let nesting = 10_000
        let source = String(repeating: "< ", count: nesting) + "T " + String(repeating: "> ", count: nesting) + "tail"
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        let node = parser.parseTypeArguments()

        #expect(parser.arena.node(node).kind == .typeArgs)
        #expect(parser.stream.index == nesting * 2 + 1)
        #expect(parser.stream.peek() == lexed.tokens[lexed.tokens.count - 2])
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif
