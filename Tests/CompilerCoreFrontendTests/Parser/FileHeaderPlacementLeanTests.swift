#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("package p\npackage p\n", false),
        ("val x = 1\npackage p\npackage p\n", true),
        ("package p\nval x = 1\npackage p\n", true),
        ("package p\nimport p.Name\npackage p\n", false),
    ])
    func repeatingPackagePreservesImportPlacement(prefix: String, late: Bool) {
        let source = prefix + "import p.Other\nfun after() {}"
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let parsed = parser.parseFile()

        #expect(parser.stream.index == lexed.tokens.count - 1)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(parsed.arena.nodes.count { $0.kind == .packageHeader } == 2)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 1)
        let diagnostics = lexed.diagnostics.diagnostics
        if late {
            #expect(diagnostics.map(\.code) == ["KSWIFTK-PARSE-0017"])
            #expect(diagnostics.first?.primaryRange?.start.offset == prefix.utf8.count)
        } else {
            #expect(diagnostics.isEmpty)
        }
    }
}
#endif
