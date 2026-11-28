#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func fileLoopCompletesLongImportRun() {
        let count = 20_000
        let lexed = lex(String(repeating: "import p.Name\n", count: count))
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        let parsed = parser.parseFile()

        #expect(parsed.arena.nodes.filter { $0.kind == .importList }.map(\.childCount) == [Int32(count)])
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(parser.stream.index == lexed.tokens.count - 1)
        #expect(parser.stream.peek().kind == .eof)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
