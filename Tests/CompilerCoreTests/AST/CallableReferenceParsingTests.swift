#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CallableReferenceParsingTests {
    @Test(arguments: ["Array<Int>?::class", "Array<Int>? ::class"])
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
        #expect(lexed.interner.resolve(member) == "echo")
        #expect(range.start.offset == 0)
        #expect(range.end.offset == source.utf8.count)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
        let typeRef = try #require(arena.callableRefReceiverTypeRef(for: exprID))
        guard case let .named(path, args, nullable) = arena.typeRef(typeRef) else {
            Issue.record("Expected a named type receiver.")
            return
        }
        #expect(lexed.interner.resolve(try #require(path.last)) == "Box")
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
        #expect(lexed.interner.resolve(member) == expectedMember)
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
}
#endif
