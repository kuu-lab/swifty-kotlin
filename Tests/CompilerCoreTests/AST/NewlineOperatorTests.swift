@testable import CompilerCore
import Testing

@Suite
struct NewlineOperatorTests {
    @Test(arguments: [
        "+", "-", "*", "/", "%", "==", "!=", "===", "!==", "<", ">", "<=", ">=",
        "..", "..<", "in", "!in", "is", "!is", "=", "+=", "-=", "*=", "/=", "%=", "->", "++", "--",
    ])
    func leadingOperatorsDoNotContinueStatements(op: String) {
        let previous = lex("value").tokens.dropLast()
        let next = lex("\(op) other").tokens.dropLast()
        #expect(!BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))
        #expect(ParserBoundaryPolicy.shouldSplitStatementOnNewline(next.first!.kind))
    }

    @Test(arguments: [".", "?.", "?:", "&&", "||", "as", "as?", ",", ")", "]"])
    func leadingContinuationsRemainSupported(op: String) {
        let previous = lex("value").tokens.dropLast()
        let next = lex("\(op) other").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))
        #expect(!ParserBoundaryPolicy.shouldSplitStatementOnNewline(next.first!.kind))
    }

    @Test(arguments: ["+", "-"])
    func unaryStatementDoesNotChangeInitializer(op: String) throws {
        let context = makeContextFromSource("""
        fun main() {
            val n = 1
            \(op) 2
            println(n)
        }
        """)
        try runFrontend(context)
        #expect(!context.diagnostics.hasError)
        let ast = try #require(context.ast)
        let function = try #require(ast.arena.declarations().compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body,
              statements.count == 3,
              case let .localDecl(_, _, _, initializer?, _, _) = ast.arena.expr(statements[0]),
              case .intLiteral(1, _) = ast.arena.expr(initializer),
              case .unaryExpr = ast.arena.expr(statements[1])
        else {
            Issue.record("The initializer and unary expression must be separate statements")
            return
        }
    }

    @Test(arguments: [
        "* 2", "/ 2", "% 2", "== 2", "!= 2", "=== 2", "!== 2", "< 2", "> 2", "<= 2", ">= 2",
        ".. 2", "..< 2", "in values", "!in values", "is Int", "!is Int", "= 2", "+= 2", "-= 2",
        "*= 2", "/= 2", "%= 2", "-> 2", "++", "--",
    ])
    func invalidLeadingOperatorsReportErrors(tail: String) throws {
        for source in [
            "fun main() {\n var n = 1\n \(tail)\n println(n)\n}",
            "fun main() { val f = {\n var n = 1\n \(tail)\n n\n} }",
            "fun main() { fun local() {\n var n = 1\n \(tail)\n println(n)\n} }",
        ] {
            let context = makeContextFromSource(source)
            try runFrontend(context)
            #expect(context.diagnostics.hasError, "Expected a parse error for \(tail)")
        }
    }

    @Test
    func cstSeparatesLeadingUnaryExpression() {
        let parsed = parse("fun main() {\n n\n + 2\n}")
        let block = parsed.arena.nodes.firstIndex { $0.kind == .block }!
        let statements = parsed.arena.children(of: NodeID(rawValue: Int32(block))).filter {
            guard case let .node(id) = $0 else { return false }
            return parsed.arena.node(id).kind == .statement
        }
        #expect(statements.count == 2)
    }

    @Test
    func declarationAssignmentContinuationIsContextual() {
        let next = lex("= 2").tokens.dropLast()
        for header in ["fun f()", "fun f(): Int", "val n: Int", "var n", "fun f(x: Int = 1): Int"] {
            #expect(BuildASTPhase.isContinuationBoundary(previousTail: lex(header).tokens.dropLast(), nextHead: next))
        }
        for expression in ["n", "val n = 1", "fun f() = 1"] {
            #expect(!BuildASTPhase.isContinuationBoundary(previousTail: lex(expression).tokens.dropLast(), nextHead: next))
        }
    }

    @Test
    func declarationAndWhenContinuationsParse() throws {
        let context = makeContextFromSource("""
        fun answer(): Int
            = 42
        val top: Int
            = 7
        fun main() {
            fun local(): Int
                = 8
            val n: Int
                = 1
            val grouped = (1
                + 2)
            val trailing = 1 +
                2
            val cast = n
                as Any
            val safeCast = cast
                as? Int
            val result = when (n) {
                1
                    -> 2
                else
                    -> 3
            }
        }
        """)
        try runFrontend(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics.map(\.message))")
    }
}
