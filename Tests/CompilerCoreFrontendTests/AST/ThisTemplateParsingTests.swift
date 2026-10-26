#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

struct ThisTemplateParsingTests {
    @Test(arguments: [#""$this""#, #""""$this""""#, #""${this}""#])
    func thisInterpolationIsAReceiverExpression(source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(tokens: lexed.tokens.dropLast(), interner: lexed.interner, astArena: arena, diagnostics: lexed.diagnostics)
        let id = try #require(parser.parse())
        guard case let .stringTemplate(parts, _) = arena.expr(id), let part = parts.first,
              case let .expression(receiver) = part, case .thisRef(label: nil, _) = arena.expr(receiver) else {
            Issue.record("Expected receiver interpolation, not an unresolved local named this.")
            return
        }
        #expect(!lexed.diagnostics.hasError)
    }
}
#endif
