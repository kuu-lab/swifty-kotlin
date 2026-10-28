#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct LocalPropertyNewlineLambdaParsingTests {
    @Test
    func superArgumentInlineLambdaKeepsLocalAndLambdaSeparate() throws {
        let (ast, ctx) = try buildASTModule(from: """
        inline fun <T> run(block: () -> T): T = block()
        open class Base(val callback: () -> String)
        class Outer {
            val ok = "OK"
            inner class Inner : Base(
                run {
                    val value = ok
                    { value }
                }
            )
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-PARSE-") })
        let outer = try #require(ast.arena.declarations().compactMap { declaration -> ClassDecl? in
            guard case let .classDecl(classDecl) = declaration,
                  classDecl.name == ctx.interner.intern("Outer")
            else {
                return nil
            }
            return classDecl
        }.first)
        let innerDecl = try #require(outer.nestedClasses.first)
        guard case let .classDecl(inner) = try #require(ast.arena.decl(innerDecl)),
              let superArgument = inner.superTypeEntries.first?.constructorArgs.first?.expr
        else {
            Issue.record("Expected Inner to have a first super-constructor argument")
            return
        }
        guard case let .call(callee, _, runArguments, _) = ast.arena.expr(superArgument) else {
            Issue.record("Expected run call as super argument, got \(String(describing: ast.arena.expr(superArgument)))")
            return
        }
        guard case let .nameRef(runName, _) = ast.arena.expr(callee),
              runName == ctx.interner.intern("run"),
              case let .lambdaLiteral(_, lambdaBody, _, _) = ast.arena.expr(try #require(runArguments.first).expr),
              case let .blockExpr(statements, trailing, _) = ast.arena.expr(lambdaBody)
        else {
            Issue.record("Expected the run argument to be a lambda with a block body")
            return
        }
        guard statements.count == 1,
              case let .localDecl(valueName, _, _, initializer?, _, _, _) = ast.arena.expr(try #require(statements.first)),
              valueName == ctx.interner.intern("value"),
              case let .nameRef(propertyName, _) = ast.arena.expr(initializer),
              propertyName == ctx.interner.intern("ok"),
              case .lambdaLiteral = ast.arena.expr(try #require(trailing))
        else {
            Issue.record("Expected the super argument to retain the local and following lambda as separate expressions")
            return
        }
    }

    @Test
    func callInitializerCanStillReceiveTrailingLambdaAcrossNewline() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun produce(): Int = 1
        fun sample() {
            val value = produce()
            { 42 }
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-PARSE-") })
        let sample = try #require(ast.arena.declarations().compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration,
                  function.name == ctx.interner.intern("sample")
            else {
                return nil
            }
            return function
        }.first)
        guard case let .block(statements, _) = sample.body
        else {
            Issue.record("Expected sample to retain its block body")
            return
        }
        guard statements.count == 1,
              case let .localDecl(valueName, _, _, initializer?, _, _, _) = ast.arena.expr(try #require(statements.first)),
              valueName == ctx.interner.intern("value"),
              case let .call(_, _, arguments, _) = ast.arena.expr(initializer)
        else {
            Issue.record("Expected the call initializer and following lambda to remain in one declaration")
            return
        }
        let hasTrailingLambdaArgument = arguments.contains { argument in
            guard argument.isTrailingLambda else { return false }
            if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                return true
            }
            return false
        }
        guard hasTrailingLambdaArgument else {
            Issue.record("Expected the following lambda to remain attached to the call initializer")
            return
        }
    }
}
#endif
