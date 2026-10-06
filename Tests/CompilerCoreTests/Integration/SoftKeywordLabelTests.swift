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
            case let .forExpr(_, _, _, label?, range), let .whileExpr(_, _, label?, range),
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
