#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct RawStringLineEndingNormalizationTests {
    private func parseExpression(_ source: String) throws
        -> (expr: ExprID, arena: ASTArena, interner: StringInterner)
    {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        let expr = try #require(parser.parse())
        return (expr, arena, lexed.interner)
    }

    @Test
    func rawStringCRLFNormalizesToLF() throws {
        let (expr, arena, interner) = try parseExpression("\"\"\"line1\r\nline2\"\"\"")
        guard case let .stringLiteral(id, _) = arena.expr(expr) else {
            Issue.record("Expected .stringLiteral")
            return
        }
        let value = interner.resolve(id)
        #expect(value == "line1\nline2")
    }

    @Test
    func rawStringCRNormalizesToLF() throws {
        let (expr, arena, interner) = try parseExpression("\"\"\"line1\rline2\"\"\"")
        guard case let .stringLiteral(id, _) = arena.expr(expr) else {
            Issue.record("Expected .stringLiteral")
            return
        }
        let value = interner.resolve(id)
        #expect(value == "line1\nline2")
    }

    @Test
    func rawStringLFUnchanged() throws {
        let (expr, arena, interner) = try parseExpression("\"\"\"line1\nline2\"\"\"")
        guard case let .stringLiteral(id, _) = arena.expr(expr) else {
            Issue.record("Expected .stringLiteral")
            return
        }
        let value = interner.resolve(id)
        #expect(value == "line1\nline2")
    }

    @Test
    func rawStringMixedLineEndings() throws {
        let (expr, arena, interner) = try parseExpression("\"\"\"a\r\nb\rc\nd\"\"\"")
        guard case let .stringLiteral(id, _) = arena.expr(expr) else {
            Issue.record("Expected .stringLiteral")
            return
        }
        let value = interner.resolve(id)
        #expect(value == "a\nb\nc\nd")
    }

    @Test
    func rawStringTemplateCRLFNormalizes() throws {
        let source = "\"\"\"line1\r\n${x}\r\nline3\"\"\""
        let (expr, arena, interner) = try parseExpression(source)
        guard case let .stringTemplate(parts, _) = arena.expr(expr) else {
            Issue.record("Expected .stringTemplate")
            return
        }
        // First literal part should have LF, not CRLF
        guard case let .literal(firstID) = parts[0] else {
            Issue.record("Expected first part to be literal")
            return
        }
        let firstValue = interner.resolve(firstID)
        #expect(firstValue == "line1\n")
    }

    @Test
    func regularStringEscapeNotAffected() throws {
        // Regular strings with \r\n escapes should NOT be normalized
        // (they're escape sequences, not literal line breaks)
        let (expr, arena, interner) = try parseExpression("\"a\\r\\nb\"")
        guard case let .stringLiteral(id, _) = arena.expr(expr) else {
            Issue.record("Expected .stringLiteral")
            return
        }
        let value = interner.resolve(id)
        #expect(value == "a\r\nb")
    }

    @Test
    func multiDollarRawStringCRLFNormalizes() throws {
        let (expr, arena, interner) = try parseExpression("$$\"\"\"line1\r\nline2\"\"\"")
        guard case let .stringLiteral(id, _) = arena.expr(expr) else {
            Issue.record("Expected .stringLiteral")
            return
        }
        let value = interner.resolve(id)
        #expect(value == "line1\nline2")
    }
}
#endif
