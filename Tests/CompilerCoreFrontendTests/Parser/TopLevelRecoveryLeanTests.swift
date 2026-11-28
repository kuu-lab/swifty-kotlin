#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("junk fun next", 0, 0, 1 as Int?, false),
        ("junk\nval next", 0, 0, 1, false),
        ("junk", 0, 0, 1, false),
        ("} fun next", 0, 0, 1, false),
        ("fun next", 0, 0, 0, true),
        ("val next", 0, 0, 0, true),
        ("anchor fun next", 1, 1, 0, true),
        ("anchor fun next", 0, 1, nil, false),
        ("anchor", 0, 1, nil, false),
        ("", 0, 0, 0, false),
    ])
    func topLevelRecoverySelectsOnlyRequiredAction(
        source: String, before: Int, after: Int, skipped: Int?, forceAdvance: Bool
    ) {
        let lexed = lex(source)
        for tokens in [lexed.tokens, Array(lexed.tokens.dropLast())] {
            let parser = KotlinParser(tokens: tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            for _ in 0..<after {
                _ = parser.stream.advance()
            }
            let plan = LeanParser.topLevelRecovery(parser, before: before)
            #expect(plan?.skippedCount == skipped)
            #expect((plan?.forceAdvance ?? false) == forceAdvance)
            #expect(parser.stream.index == after)
            #expect(parser.arena.tokens.isEmpty)
        }
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func extraneousTopLevelBraceRecoversBeforeNextDeclaration() throws {
        let source = "}\nfun after() {}"
        let parsed = parse(source)
        let nodes = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }
        #expect(nodes.map(\.kind) == [.statement, .funDecl])
        #expect(nodes.first?.range.end.offset == 1)
        #expect(nodes.last?.range.start.offset == 2)
        let diagnostic = try #require(parsed.diagnostics.diagnostics.first)
        #expect(parsed.diagnostics.diagnostics.count == 1)
        #expect(diagnostic.code == "KSWIFTK-PARSE-0006")
        #expect(diagnostic.message == "Skipped 1 unexpected token(s).")
        #expect(diagnostic.primaryRange == parsed.tokens[0].range)
        #expect(!parsed.arena.tokens.contains { $0.kind == .eof })
    }
}
#endif
