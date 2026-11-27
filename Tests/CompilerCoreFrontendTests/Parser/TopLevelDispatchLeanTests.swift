#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: ["context", "annotation", "modifier"])
    func exhaustedTopLevelLookaheadRecoversThroughParseFile(prefix: String) throws {
        let work = KotlinParser.declarationLookaheadWorkLimit
        let exhausted = switch prefix {
        case "context": "context(" + String(repeating: "x, ", count: work) + "x)"
        case "annotation": "@Tag(" + String(repeating: "1, ", count: work) + "1)"
        default: String(repeating: "private\n", count: work + 1)
        }
        let source = exhausted + "\nfun after() {}"
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let parsed = parser.parseFile()
        let root = parsed.arena.node(parsed.root)
        let functions = parsed.arena.children(of: parsed.root).compactMap { child -> NodeID? in
            guard case let .node(id) = child, parsed.arena.node(id).kind == .funDecl else { return nil }
            return id
        }
        #expect(functions.count == 1)
        let function = try #require(functions.first)
        let keywordOffsets = parsed.arena.children(of: function).compactMap { child -> Int? in
            guard case let .token(id) = child,
                  let token = parsed.arena.token(id), token.kind == .keyword(.fun)
            else { return nil }
            return token.range.start.offset
        }

        #expect(root.kind == .script)
        #expect(keywordOffsets == [exhausted.utf8.count + 1])
        #expect(lexed.diagnostics.diagnostics.count { $0.code == "KSWIFTK-PARSE-0007" } == 1)
        #expect(!lexed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0032" })
        #expect(parser.stream.index == lexed.tokens.count - 1)
        #expect(parser.stream.peek().kind == .eof)
    }
}
#endif
