#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: ["for (i in xs) use(i)", "while (ready) work()", "do work() while (ready)"])
    func loopKeywordsStillDispatchToLoopStatements(source: String) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let node = parser.parseStatement(inBlock: false)

        #expect(parser.arena.node(node).kind == .loopStmt)
        #expect(parser.stream.peek().kind == .eof)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
