#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct SoftKeywordLabelTests {
    // KUU-1266: every reported keyword, plus remaining simpleIdentifier controls.
    static let names = [
        "inner", "data", "value", "lateinit", "open", "final", "abstract", "sealed",
        "enum", "annotation", "operator", "infix", "inline", "tailrec", "vararg",
        "const", "private", "public", "internal", "protected", "companion", "init",
        "field", "expect", "actual", "crossinline", "noinline", "reified", "out",
        "by", "where", "file", "property", "receiver", "param", "delegate", "catch",
        "finally", "external", "dynamic", "import", "constructor", "get", "set",
        "suspend", "override", "setparam", "context", "of", "header", "impl", "it",
        "ordinary", "`when`", "`label name`",
    ]

    @Test(arguments: names)
    func preservesDefinitionsAndReferences(name: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun test() {
            \(name)@ for (i in 1..3) { break@\(name) }
            \(name)@ while (true) { continue@\(name) }
            \(name)@ do { break@\(name) } while (false)
            val action = \(name)@{ return@\(name) 7 }
            visit \(name)@{ this@\(name) }
        }
        """, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let expected = name.replacingOccurrences(of: "`", with: "")
        let expressions = ast.arena.exprs
        // CST reconstruction can leave duplicate intermediate expressions in the arena.
        var labels: [Int: String] = [:]
        var jumps: [Int: String] = [:]
        for expression in expressions {
            switch expression {
            case let .forExpr(_, _, _, _, label?, range), let .whileExpr(_, _, label?, range),
                 let .doWhileExpr(_, _, label?, range), let .lambdaLiteral(_, _, label?, range):
                labels[range.start.offset] = ctx.interner.resolve(label)
            case let .breakExpr(label?, range), let .continueExpr(label?, range),
                 let .returnExpr(_, label?, range), let .thisRef(label?, range):
                jumps[range.start.offset] = ctx.interner.resolve(label)
            default:
                break
            }
        }
        #expect(labels.count == 5)
        #expect(labels.values.allSatisfy { $0 == expected })
        #expect(jumps.count == 5)
        #expect(jumps.values.allSatisfy { $0 == expected })
    }

    @Test(arguments: names)
    func preservesExpressionBodyLambda(name: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun test() =
            \(name)@{ return@\(name) 7 }
        """, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body,
              case let .lambdaLiteral(_, _, label?, _) = ast.arena.expr(body) else {
            Issue.record("Expected a labeled lambda expression body")
            return
        }
        #expect(ctx.interner.resolve(label) == name.replacingOccurrences(of: "`", with: ""))
    }

    @Test func valueExpressionLabelsDoNotBecomeNameReferences() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun box(): String {
            var s1 = (l1@ "s")
            val s2 = (l2@ if (l3@ true) s1 else null)
            return if (s2 == "s") "OK" else "fail"
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let labels = Set(["l1", "l2", "l3"].map(ctx.interner.intern))
        let labelReferences = ast.arena.exprs.compactMap { expression -> InternedString? in
            guard case let .nameRef(name, _) = expression, labels.contains(name) else { return nil }
            return name
        }
        #expect(labelReferences.isEmpty, "Expression labels must not remain as value references")
    }

    @Test(arguments: ["val", "var"])
    func labelBeforeLocalPropertyKeepsItAsADeclaration(keyword: String) throws {
        let source = """
        fun test(): Int {
            x@ \(keyword) a = 1; return a
        }
        """
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body,
              statements.count == 2,
              case let .localDecl(name, isMutable, _, _, _, _, _) = ast.arena.expr(statements[0]) else {
            Issue.record("Expected the labeled property to remain a local declaration")
            return
        }
        #expect(ctx.interner.resolve(name) == "a")
        #expect(isMutable == (keyword == "var"))
    }

    @Test(arguments: ["catch", "finally"])
    func labelAfterTryIsANewStatement(name: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun test() {
            try {} catch (e: Exception) {} finally {}
            \(name)@ while (false) { break@\(name) }
        }
        """, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body else {
            Issue.record("Expected a block body")
            return
        }
        #expect(statements.count == 2)
        guard let last = statements.last,
              case let .whileExpr(_, _, label?, _) = ast.arena.expr(last) else {
            Issue.record("Expected a labeled loop following try")
            return
        }
        #expect(ctx.interner.resolve(label) == name)
    }

    @Test(arguments: ["catch", "finally"])
    func jumpLabelDoesNotContinueNextStatement(name: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun test() {
            \(name)@ do {
                if (false) continue@\(name)
                break@\(name)
            } while (true)
        }
        """, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body,
              let loop = statements.first,
              case let .doWhileExpr(body, _, _, _) = ast.arena.expr(loop),
              case let .blockExpr(bodyStatements, last?, _) = ast.arena.expr(body),
              case let .breakExpr(label?, _) = ast.arena.expr(last) else {
            Issue.record("Expected a separate break after the labeled continue")
            return
        }
        #expect(bodyStatements.count == 1)
        #expect(ctx.interner.resolve(label) == name)
    }
}
#endif
