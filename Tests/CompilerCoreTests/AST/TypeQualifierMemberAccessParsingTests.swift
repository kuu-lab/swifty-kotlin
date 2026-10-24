#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct TypeQualifierMemberAccessParsingTests {
    /// KUU-3238: `G<Int>.GI()` must parse as a member access whose receiver
    /// is the type-argument-bearing classifier `G<Int>`, not error out with
    /// KSWIFTK-PARSE-0001 at the member name. The receiver keeps the generic
    /// arguments on a marked `.call`, the same side-channel a callable
    /// reference uses for its type receiver.
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

    /// `G<Int>.GI()` carries explicit parentheses, so the member access must
    /// keep the explicit-call marker that distinguishes `Owner.Nested()` from
    /// the bare classifier `Owner.Nested`.
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

    /// `pkg.G<Int>.GI()` and `a.b<T>.c` keep their generic arguments on
    /// `memberCall.typeArgs`; the marker only covers the single-name form
    /// (`G<Int>`) that a `memberCall` cannot represent.
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

    /// Comparisons, generic calls, trailing lambdas and callable references
    /// must keep their existing AST shapes — only `expr<Args>.` introduces a
    /// type-qualifier call.
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

    /// The exact KUU-3238 reproduction must pass the parser: kotlinc accepts
    /// the syntax and only rejects the inner-class constructor call
    /// semantically, so the KSWIFTK-PARSE-0001 at the member name is the
    /// parity bug.
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

    /// A non-inner nested class through a generic qualifier resolves and
    /// constructs (kotlinc reports a deprecated-qualifier diagnostic instead;
    /// the inverse-parity gap is tracked separately).
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
