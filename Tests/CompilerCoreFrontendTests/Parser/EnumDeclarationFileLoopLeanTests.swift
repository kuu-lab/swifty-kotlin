@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func fileLoopKeepsEnumAndCompanionAsDeclarations() throws {
        let lexed = lex("enum class E { A; companion object {} }")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let (arena, root) = parser.parseFile()
        let declarations = arena.children(of: root).compactMap { child -> NodeID? in
            guard case let .node(id) = child else { return nil }
            return id
        }
        #expect(arena.node(root).kind == .kotlinFile)
        #expect(declarations.map { arena.node($0).kind } == [.classDecl])
        let declaration = try #require(declarations.first)
        let body = try #require(arena.children(of: declaration).compactMap { child -> NodeID? in
            guard case let .node(id) = child, arena.node(id).kind == .block else { return nil }
            return id
        }.first)
        let members = arena.children(of: body).compactMap { child -> SyntaxKind? in
            guard case let .node(id) = child else { return nil }
            return arena.node(id).kind
        }
        #expect(members == [.enumEntry, .objectDecl])
        #expect(parser.stream.index == lexed.tokens.count - 1)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
