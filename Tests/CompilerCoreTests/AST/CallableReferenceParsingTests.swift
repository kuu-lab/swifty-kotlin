#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CallableReferenceParsingTests {
    @Test(arguments: [
        "Array<Int>?::class", "Array<Int>? ::class", "BooleanArray?::contentToString",
        "BooleanArray? ::contentEquals", "kotlin.IntArray?::contentToString",
    ])
    func nullableTypeReceiverPreservesQuestionMark(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let expr = try #require(parser.parse())
        let ref = try #require(arena.callableRefReceiverTypeRef(for: expr))
        guard case let .named(_, _, nullable) = arena.typeRef(ref) else {
            Issue.record("Expected a named type receiver")
            return
        }
        #expect(nullable)
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: [
        "Box<String>::echo", "pkg.Box<String>::echo", "Outer.Box<List<String?>>::echo",
        "Box<*>::echo", "Box<out String>::echo", "Box<(Int) -> String>::echo",
    ])
    func explicitTypeReceiverPreservesTypeArguments(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        guard case let .callableRef(receiver, member, range) = arena.expr(exprID) else {
            Issue.record("Expected a callable reference, not a comparison.")
            return
        }
        #expect(receiver != nil)
        #expect(member == lexed.interner.intern("echo"))
        #expect(range.start.offset == 0)
        #expect(range.end.offset == source.utf8.count)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
        let typeRef = try #require(arena.callableRefReceiverTypeRef(for: exprID))
        guard case let .named(path, args, nullable) = arena.typeRef(typeRef) else {
            Issue.record("Expected a named type receiver.")
            return
        }
        let typeName = try #require(path.last)
        #expect(typeName == lexed.interner.intern("Box"))
        #expect(args.count == 1)
        #expect(!nullable)
        let encoded = try JSONEncoder().encode(arena.snapshot())
        let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: encoded))
        #expect(restored.callableRefReceiverTypeRef(for: exprID) == typeRef)
        #expect(restored.typeRef(typeRef) == arena.typeRef(typeRef))
    }

    @Test(arguments: ["a < b", "a > b", "a < b && c > d", "Box<String>()::echo", "box::echo"])
    func ordinaryExpressionsDoNotAcquireTypeReceivers(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        _ = try #require(parser.parse())
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
        #expect(arena.snapshot().callableRefReceiverTypeRefs.isEmpty)
    }

    @Test(arguments: [
        "::", "x::", "println(\"d\")::",
        "(::)", "(x::)", "consume(::)", "consume(x::)",
        "consume(::, 1)", "consume(x::, 1)", "(:: + 1)", "(x:: + 1)",
    ])
    func missingMemberReportsParseError(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(lexed.diagnostics.diagnostics.first)
        let opToken = try #require(lexed.tokens.first { $0.kind == .symbol(.doubleColon) })
        #expect(diagnostic.code == "KSWIFTK-PARSE-0014")
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected an identifier after '::'.")
        #expect(diagnostic.primaryRange == opToken.range)
        #expect(!arena.exprs.contains { if case .callableRef = $0 { true } else { false } })
    }

    @Test(arguments: ["::", "x::"])
    func missingMemberAtEOFReportsOnce(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens,
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.count == 1)
        #expect(lexed.diagnostics.diagnostics.first?.code == "KSWIFTK-PARSE-0014")
        #expect(parser.current()?.kind == .eof)
    }

    @Test(arguments: ["::)", "::,", "::+", "::42"])
    func missingMemberLeavesUnexpectedTokenForRecovery(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens,
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parseCallableReference() == nil)
        #expect(parser.index == 1)
        #expect(parser.current() == lexed.tokens[1])
        #expect(lexed.diagnostics.diagnostics.count == 1)
    }

    @Test(arguments: [
        "::target", "receiver::target", "::`when`", "receiver::`when`",
        "::get", "receiver::get", "::suspend", "receiver::suspend", "String::class",
    ])
    func validMemberPreservesCallableReference(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        guard case let .callableRef(receiver, member, range) = arena.expr(exprID) else {
            Issue.record("Expected a callable reference.")
            return
        }

        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect((receiver == nil) == source.hasPrefix("::"))
        let expectedMember = source.components(separatedBy: "::")[1].replacingOccurrences(of: "`", with: "")
        #expect(member == lexed.interner.intern(expectedMember))
        #expect(range.start.offset == 0)
        #expect(range.end.offset == source.utf8.count)
        #expect(parser.current() == nil)
    }

    @Test(arguments: [
        "fun main() { :: }",
        "fun main() { println(\"d\"):: }",
        "fun main() { val x = 1; x:: }",
        "fun main() { val r = :: }",
        "fun main() { val x = 1; val r = x:: }",
        "fun main() { consume(::) }",
        "fun main() { println(\"d\")\n:: }",
        "fun main() { val r = { :: } }",
        "fun ref() = ::",
        "val r = ::",
        "fun main() {\n::\nprintln(\"d\")::\nval r = ::\n}",
    ])
    func frontendRejectsMissingMember(_ source: String) throws {
        let (_, ctx) = try buildASTModule(from: source, includeStdlib: false)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0014" && $0.severity == .error
        })
    }

    /// KUU-1376: `T::class.findAssociatedObject<A>()` hung the parser. After a
    /// consumed `::class`, the `<` suffix re-matched the already-folded `::`
    /// in `tryParseCallableReferenceTypeReceiver`, rewound `index`, and the
    /// postfix loop re-parsed `.member<` forever. A `::` behind the cursor is
    /// already consumed, so the `<A>` must fall through to ordinary member
    /// type arguments.
    @Test(arguments: [
        "Tgt::class.findAssociatedObject<AOK>()",
        "Tgt::class.findAnnotation<AOK>()",
        "Tgt::class.member<AOK>",
        "a.b<T>::c.d<E>::f",
    ])
    func memberTypeArgsAfterCallableReferenceDoNotRewind(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)

        if source.hasSuffix("::f") {
            guard case let .callableRef(receiver, member, _) = arena.expr(exprID) else {
                Issue.record("Expected a callable reference")
                return
            }
            #expect(member == lexed.interner.intern("f"))
            guard case .memberCall = arena.expr(try #require(receiver)) else {
                Issue.record("Expected a member-call receiver")
                return
            }
            return
        }

        guard case let .memberCall(receiver, callee, typeArgs, _, _) = arena.expr(exprID) else {
            Issue.record("Expected a member call")
            return
        }
        #expect(typeArgs.count == 1)
        let className = KnownCompilerNames(interner: lexed.interner).className
        #expect(callee != className)
        guard case let .callableRef(_, classMember, _) = arena.expr(receiver) else {
            Issue.record("Expected a callable-ref receiver")
            return
        }
        #expect(classMember == className)
    }

    /// KUU-1376 (sibling path): an infix `<` after `T::class` hit the same
    /// rewind loop through the top-level `<` branch of parsePostfixSuffixes.
    @Test
    func infixLessThanAfterCallableReferenceDoesNotRewind() throws {
        let lexed = lex("A::class < B::class")
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let exprID = try #require(parser.parse())
        guard case let .binary(op, lhs, rhs, _) = arena.expr(exprID) else {
            Issue.record("Expected a binary comparison")
            return
        }
        #expect(op == .lessThan)
        let className = KnownCompilerNames(interner: lexed.interner).className
        for side in [lhs, rhs] {
            guard case let .callableRef(_, member, _) = arena.expr(side) else {
                Issue.record("Expected callable-ref operands")
                return
            }
            #expect(member == className)
        }
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(arena.snapshot().callableRefReceiverTypeRefs.isEmpty)
    }
}
#endif
