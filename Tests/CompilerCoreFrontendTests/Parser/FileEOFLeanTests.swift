#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("", [Int]()),
        ("// comment\n", []),
        ("import p.A", [1]),
        ("import p.A\nimport p.B", [2]),
        ("import p.A\npackage p", [1]),
        ("import p.A\npackage p\nimport p.B\nimport p.C", [1, 2]),
    ])
    func fileEOFFinalizesImportsWithoutConsumingEOF(source: String, groupSizes: [Int]) {
        let lexed = lex(source)
        for tokens in [lexed.tokens, Array(lexed.tokens.dropLast())] {
            let diagnostics = DiagnosticEngine()
            let parser = KotlinParser(tokens: tokens, interner: lexed.interner, diagnostics: diagnostics)
            let parsed = parser.parseFile()
            let groups = parsed.arena.children(of: parsed.root).compactMap { child -> NodeID? in
                guard case let .node(id) = child, parsed.arena.node(id).kind == .importList else { return nil }
                return id
            }

            #expect(groups.map { parsed.arena.children(of: $0).count } == groupSizes)
            #expect(parser.stream.index == lexed.tokens.count - 1)
            #expect(parser.stream.peek().kind == .eof)
            #expect(!parsed.arena.tokens.contains { $0.kind == .eof })
            #expect(diagnostics.diagnostics.isEmpty)
        }
    }

    @Test
    func fileEOFStopsBeforeLaterTokensAndFinishesPendingImports() throws {
        let lexed = lex("import p.A\nimport p.B\nfun after() {}")
        let stop = try #require(lexed.tokens.firstIndex { $0.kind == .keyword(.fun) })
        var tokens = lexed.tokens
        tokens.insert(try #require(lexed.tokens.last), at: stop)
        let parser = KotlinParser(tokens: tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let parsed = parser.parseFile()
        let groups = parsed.arena.nodes.filter { $0.kind == .importList }

        #expect(parser.stream.index == stop)
        #expect(parser.stream.peek().kind == .eof)
        #expect(groups.map(\.childCount) == [2])
        #expect(!parsed.arena.nodes.contains { $0.kind == .funDecl })
        #expect(!parsed.arena.tokens.contains { $0.kind == .eof })
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
