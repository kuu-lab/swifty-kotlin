@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func bundledFileLoopMatchesSwiftAfterUnmatchedClosingBrace() {
        let lexed = lex("}\nfun next() {}")
        let swift = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        let lean = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        let expected = swift.parseFile()
        let assembly = KotlinParser.FileAssembly(lean)
        let root = assembly.finish(LeanParser.parseFile(lean, assembly: assembly))

        #expect(swift.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0006"])
        #expect(lean.diagnostics.diagnostics == swift.diagnostics.diagnostics)
        #expect(lean.stream.index == swift.stream.index)
        #expect(lean.arena.tokens == expected.arena.tokens)
        #expect(lean.arena.node(root).kind == expected.arena.node(expected.root).kind)
    }
}
