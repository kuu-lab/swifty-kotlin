@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct NewlineOperatorTests {
    @Test(arguments: ["return@action total", "if (ready) return@action total", "return@action left plus right"])
    func labeledReturnDoesNotAbsorbFollowingStatement(source: String) {
        let previous = lex(source).tokens.dropLast()
        let next = lex("total").tokens.dropLast()
        #expect(!BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))
    }

    @Test(arguments: ["return@action total plus", "this@outer plus"])
    func labeledExpressionsKeepPendingInfixContinuation(source: String) {
        let previous = lex(source).tokens.dropLast()
        let next = lex("total").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))
    }

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

    @Test
    func newlineBeforeDoWhileConditionContinuesExpression() {
        let previous = lex("do { value = \"x\" }").tokens.dropLast()
        let next = lex("while (value != \"Y\")").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))

        let labeledPrevious = lex("loop@ do { value = \"x\" }").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: labeledPrevious, nextHead: next))

        let unrelatedBlock = lex("if (ready) { value = \"x\" }").tokens.dropLast()
        #expect(!BuildASTPhase.isContinuationBoundary(previousTail: unrelatedBlock, nextHead: next))
    }

    @Test(arguments: [
        "for (i in 0 until 3) {}",
        "while (true) {}",
        "do {} while (false)",
    ])
    func lineSeparatedLoopLabelBindsToFollowingLoop(loopSource: String) throws {
        let (ast, context) = try buildASTModule(from: """
        fun test() {
            outer@
            \(loopSource)
        }
        """, includeStdlib: false)
        let function = try #require(topLevelFunction(named: "test", in: ast, interner: context.interner))

        guard case let .block(statements, _) = function.body,
              statements.count == 1,
              let loop = statements.first
        else {
            Issue.record("The label and loop must parse as one statement")
            return
        }

        let label: InternedString?
        switch ast.arena.expr(loop) {
        case let .forExpr(_, _, _, loopLabel, _),
             let .whileExpr(_, _, loopLabel, _),
             let .doWhileExpr(_, _, loopLabel, _):
            label = loopLabel
        default:
            Issue.record("Expected the labeled statement to be a loop")
            return
        }
        #expect(label == context.interner.intern("outer"))
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
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics.map(\.message))")
        let ast = try #require(context.ast)
        let function = try #require(ast.arena.declarations().compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body,
              statements.count == 3,
              case let .localDecl(_, _, _, initializer?, _, _, _) = ast.arena.expr(statements[0]),
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

    @Test(arguments: ["+", "-"])
    func cstSeparatesLeadingUnaryAfterBlockBodiedLocalFunction(op: String) {
        // A `{ }`-bodied local function followed by a newline `+x`/`-x` is two
        // statements: the declaration, then a prefix-unary expression. The
        // trailing-lambda continuation `f() { } + x` only applies on the same
        // line, so the `+`/`-` line must not be absorbed into the declaration.
        let parsed = parse("fun f() {\n    fun String.unary() { }\n    \(op) \"OK\"\n}")
        let outerBlockIndex = parsed.arena.nodes.indices.first { index in
            guard parsed.arena.nodes[index].kind == .block else { return false }
            return parsed.arena.children(of: NodeID(rawValue: Int32(index))).contains { child in
                guard case let .node(id) = child else { return false }
                return parsed.arena.node(id).kind == .funDecl
            }
        }!
        let statementLike = parsed.arena.children(of: NodeID(rawValue: Int32(outerBlockIndex))).filter { child in
            guard case let .node(id) = child else { return false }
            return parsed.arena.node(id).kind == .funDecl
                || parsed.arena.node(id).kind == .statement
        }
        #expect(statementLike.count == 2)
    }

    @Test
    func declarationAssignmentContinuationIsContextual() {
        let next = lex("= 2").tokens.dropLast()
        for header in ["fun f()", "fun f(): Int", "val n: Int", "var n", "fun f(x: Int = 1): Int"] {
            #expect(BuildASTPhase.isContinuationBoundary(previousTail: lex(header).tokens.dropLast(), nextHead: next))
        }
        for expression in ["n", "val n = 1", "fun f() = 1", "fun f() {}"] {
            #expect(!BuildASTPhase.isContinuationBoundary(previousTail: lex(expression).tokens.dropLast(), nextHead: next))
        }
    }

    @Test
    func uninitializedLocalVariableLeavesFollowingBlockSeparate() throws {
        let declaration = lex("var value: Int").tokens.dropLast()
        let block = lex("{}").tokens.dropLast()
        #expect(!BuildASTPhase.isContinuationBoundary(previousTail: declaration, nextHead: block))

        let call = lex("run()").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: call, nextHead: block))

        let source = """
        fun test(): String {
            var value: Int
            {}
            return "OK"
        }
        """
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = context.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics.map(\.message))")
        let ast = try #require(context.ast)
        let function = try #require(ast.arena.declarations().compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body,
              statements.count == 3,
              case .localDecl(_, true, _, nil, _, _, _) = ast.arena.expr(statements[0]),
              case .lambdaLiteral = ast.arena.expr(statements[1]),
              case .returnExpr = ast.arena.expr(statements[2])
        else {
            let body: String
            if case let .block(statements, _) = function.body {
                body = statements.map { String(describing: ast.arena.expr($0)) }.joined(separator: "\n")
            } else {
                body = String(describing: function.body)
            }
            Issue.record("The uninitialized local declaration and following block must be separate statements: \(body)")
            return
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

    /// KUU-3144: a `{` that opens a new statement line is its own statement —
    /// it must not become a call argument of a bare name, a value, an indexed
    /// or parenthesized or asserted expression, or a `return` keyword.
    @Test(arguments: [
        "val tmp = Unit",
        "n",
        "xs.map",
        "val r = run",
        "a[0]",
        "(a)",
        "x!!",
        "return",
        "val tmp = 1",
    ])
    func newlineBlockDoesNotAttachToCompleteExpression(source: String) {
        let previous = lex(source).tokens.dropLast()
        let block = lex("{}").tokens.dropLast()
        #expect(!BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: block))
    }

    /// Kotlin does bind a `{` on the next line when the previous statement
    /// still awaits a braced body (declaration/literal headers, `else`,
    /// `try`, `finally`, `do`, subject-less `when`, `init`) or ends in an
    /// explicit call suffix (`name(...)`, `name<...>`).
    @Test(arguments: [
        "run()",
        "f(x)",
        "a.b()",
        "f()(x)",
        "a[i](x)",
        "f<T>()",
        "f<T>",
        "fun f()",
        "fun f(): Int",
        "object : I",
        "val o = object : I",
        "class C",
        "interface I",
        "val f = fun()",
        "x = if (a) 1 else",
        "x = try",
        "x = when",
        "label@ do",
    ])
    func newlineBlockAttachesToPendingHeaderOrCallSuffix(source: String) {
        let previous = lex(source).tokens.dropLast()
        let block = lex("{}").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: block))
    }

    @Test(arguments: [
        "val o = object : I",
        "var o: I = object : I",
        "val o = object : Outer.I",
        "val o = object : Base(), I",
    ])
    func localObjectHeaderAwaitsItsBody(source: String) {
        let previous = lex(source).tokens.dropLast()
        #expect(BuildASTPhase.canAcceptTrailingLambda(on: previous), "\(source)")
    }

    @Test(arguments: [
        "val value = Unit",
        "val value: I",
        "val type = I::class.java",
        "val o = object : I {}",
        "val result = object : I {}.value",
    ])
    func completedLocalPropertyDoesNotAwaitAnObjectBody(source: String) {
        let previous = lex(source).tokens.dropLast()
        #expect(!BuildASTPhase.canAcceptTrailingLambda(on: previous), "\(source)")
    }

    @Test
    func blockAfterUnitValueParsesAsOwnStatement() throws {
        // KUU-3144 end to end: `val tmp = Unit` + `{ }` is a declaration plus
        // a standalone lambda statement; `Unit` is never invoked.
        let context = makeContextFromSource("""
        fun test(): String {
            val tmp = Unit
            {}
            return "OK"
        }
        """)
        try runFrontend(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics.map(\.message))")
        let ast = try #require(context.ast)
        let function = try #require(ast.arena.declarations().compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body,
              statements.count == 3,
              case .localDecl = ast.arena.expr(statements[0]),
              case .lambdaLiteral = ast.arena.expr(statements[1]),
              case .returnExpr = ast.arena.expr(statements[2])
        else {
            Issue.record("The Unit value and following block must be separate statements")
            return
        }
    }

    @Test(arguments: [
        // KUU-3794: a bare `f()` call inside an infix chain counts its callee
        // and argument list as one operand. Counting them separately flipped
        // the operand/operator parity and treated the trailing identifier as
        // a pending infix name, so the next line's statement was swallowed.
        "val x = topFun() shr LOG",
        "val x = topFun() until LOG",
        "val x = topFun() to LOG",
        "val x = f() shr LOG",
        "val x = rootSize() shr local",
        "val x = a shr f() to b",
        "topFun() shr LOG",
        // An infix name followed by a parenthesised operand (`a b (c)`)
        // keeps the same parity: the trailing operand completes the chain.
        "val x = a b (c) d e",
    ])
    func bareCallOperandDoesNotMakeInfixTailPending(source: String) {
        let previous = lex(source).tokens.dropLast()
        let next = lex("return x").tokens.dropLast()
        #expect(!BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))
    }

    @Test(arguments: [
        "val x = topFun() or",
        "val x = 1 or ints[0] and",
        "x = x or",
    ])
    func infixNameAtLineEndStillContinuesStatement(source: String) {
        let previous = lex(source).tokens.dropLast()
        let next = lex("5").tokens.dropLast()
        #expect(BuildASTPhase.isContinuationBoundary(previousTail: previous, nextHead: next))
    }

    @Test
    func infixCallWithBareCallReceiverKeepsFollowingReturn() throws {
        // KUU-3794 end to end: `return x` must stay a separate block
        // statement so the function body is not judged `Unit`.
        let context = makeContextFromSource("""
        val LOG = 5
        fun topFun() = 0
        fun rootSize() = 16
        fun main(): Int {
            val local = 4
            val x = topFun() shr LOG
            val y = rootSize() shr local
            return x + y
        }
        """)
        try runFrontend(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics.map(\.message))")
        let ast = try #require(context.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: context.interner))
        guard case let .block(statements, _) = function.body,
              statements.count == 4,
              case .returnExpr = ast.arena.expr(statements[3])
        else {
            Issue.record("The return statement must remain a separate statement")
            return
        }
    }
}
