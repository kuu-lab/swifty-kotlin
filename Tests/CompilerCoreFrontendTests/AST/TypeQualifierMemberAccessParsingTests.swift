#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeQualifierMemberAccessParsingTests {
    @Test(arguments: [
        "G<Int>.GI()", "G<Int>.GI", "A<B>.C",
        "Outer<Int>.Inner.Deeper()", "G<List<Int>>.N(1)",
    ])
    func typeArgumentQualifierParsesAsMemberAccess(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
        guard case .memberCall = arena.expr(exprID) else {
            Issue.record("Expected a member call/access.")
            return
        }
        let marked = arena.snapshot().typeQualifierCallExpressions
        #expect(marked.count == 1)
        let receiver = try #require(marked.first)
        guard case let .call(_, typeArgs, args, _) = arena.expr(receiver) else {
            Issue.record("Expected the qualifier to carry its type arguments.")
            return
        }
        #expect(!typeArgs.isEmpty)
        #expect(args.isEmpty)

        let encoded = try JSONEncoder().encode(arena.snapshot())
        let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: encoded))
        #expect(restored.isTypeQualifierCall(receiver))
    }

    @Test
    func qualifiedConstructorCallKeepsExplicitCallMarker() throws {
        let lexed = lex("G<Int>.GI()")
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        guard case .memberCall = arena.expr(exprID) else {
            Issue.record("Expected a member call.")
            return
        }
        #expect(arena.isExplicitCall(exprID))
        let bare = lex("G<Int>.GI")
        let bareArena = ASTArena()
        let bareParser = BuildASTPhase.ExpressionParser(
            tokens: bare.tokens.dropLast(), interner: bare.interner,
            astArena: bareArena, diagnostics: bare.diagnostics
        )
        let bareID = try #require(bareParser.parse())
        guard case .memberCall = bareArena.expr(bareID) else {
            Issue.record("Expected a member access.")
            return
        }
        #expect(!bareArena.isExplicitCall(bareID))
    }

    @Test(arguments: ["a.b<T>.c", "pkg.G<Int>.GI()"])
    func multiSegmentQualifierKeepsMemberTypeArguments(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
        guard case let .memberCall(receiver, _, _, _, _) = arena.expr(exprID) else {
            Issue.record("Expected a member access.")
            return
        }
        guard case let .memberCall(_, _, typeArgs, _, _) = arena.expr(receiver) else {
            Issue.record("Expected the inner qualifier to stay a member call.")
            return
        }
        #expect(typeArgs.count == 1)
        #expect(arena.snapshot().typeQualifierCallExpressions.isEmpty)
    }

    @Test(arguments: [
        "a < b", "a < b > c", "a > b", "f<Int>()", "f<Int> { 1 }",
        "Box<String>::echo", "g<Int>() + h<Int>()", "list[0] < x",
    ])
    func ordinaryExpressionsAcquireNoTypeQualifierCalls(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        _ = try #require(parser.parse())
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
        #expect(arena.snapshot().typeQualifierCallExpressions.isEmpty)
    }

    @Test
    func innerClassQualifiedConstructorParsesWithoutError() throws {
        let source = """
        class G<T> { inner class GI }
        fun main() { G<Int>.GI() }
        """
        let (_, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(!ctx.diagnostics.diagnostics.contains {
            $0.code.hasPrefix("KSWIFTK-PARSE")
        })
    }

    @Test
    func nestedClassQualifiedConstructorResolves() throws {
        let source = """
        class G<T> { class N(val v: Int) }
        fun main() { val x = G<Int>.N(7) }
        """
        let (_, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(!ctx.diagnostics.diagnostics.contains {
            $0.severity == .error
        })
    }
}
#endif
