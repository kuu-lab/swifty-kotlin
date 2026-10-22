#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AssignmentInValuePositionTests {
    @Test(arguments: [
        "x = 5",
        "x += 5",
        "x -= 5",
        "x *= 5",
        "x /= 5",
        "x %= 5",
        "(x = 5)",
        "(x += 5)",
        "(x -= 5)",
        "(x *= 5)",
        "(x /= 5)",
        "x++ = 5",
        "a + (x = 1)",
    ])
    func rejectsAssignmentOperatorInExpressionSlice(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0018"
        })
        let assignToken = try #require(lexed.tokens.first { token in
            switch token.kind {
            case .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
                 .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign):
                true
            default:
                false
            }
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Unexpected token after expression.")
        #expect(diagnostic.primaryRange?.start.offset == assignToken.range.start.offset)
    }

    @Test(arguments: [
        "x == 5",
        "f(x = 5)",
        "{ x = 5 }",
        "{ x = y++ }",
        "{ x++ }",
        "when (x) { 1 -> y = 5 }",
        "when (x) { 1 -> y += 5 }",
        "when (x) { 1 -> a[i] = v }",
    ])
    func acceptsStatementPositionAssignmentsAndNamedArguments(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
    }

    @Test(arguments: [
        "x = (x += 5)",
        "x = y = 5",
        "x = (y = 5)",
        "x += y = 5",
        "x += y += 5",
        "val z = x = 3",
        "fun g() = x = 5",
        "return x = 5",
        "a[i] = x = 5",
        "c.v = x = 5",
        "for (i in x = 1..3) println(i)",
        "for ((a, b) in x = p) println(a)",
        "val s = \"a${x = 5}b\"",
    ])
    func frontendRejectsAssignmentInValuePosition(_ statement: String) throws {
        let source = """
        fun main() {
            var x = 0
            var y = 0
            \(statement)
        }
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-PARSE-0018" && $0.severity == .error
        }
        #expect(diagnostics.count == 1)
    }
}
#endif
