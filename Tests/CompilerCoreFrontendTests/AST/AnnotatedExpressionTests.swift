import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnnotatedExpressionTests {
    @Test
    func annotatedPropertyInitializerRetainsPropertyAndCall() throws {
        let (ast, ctx) = try buildASTModule(from: """
        val foo = @Suppress("X") Foo(42, "OK")
        """, includeStdlib: false)
        let property = try #require(ast.arena.decls.compactMap { decl -> PropertyDecl? in
            guard case let .propertyDecl(value) = decl,
                  ctx.interner.resolve(value.name) == "foo" else { return nil }
            return value
        }.first)
        let initializer = try #require(property.initializer)
        guard case let .call(callee, _, arguments, _) = ast.arena.expr(initializer),
              case let .nameRef(name, _) = ast.arena.expr(callee) else {
            Issue.record("Expected the annotated constructor call as the property initializer")
            return
        }
        #expect(ctx.interner.resolve(name) == "Foo")
        #expect(arguments.count == 2)
        #expect(ast.arena.expressionAnnotations(for: initializer).map(\.name) == ["Suppress"])
    }

    @Test
    func annotatedLocalInitializerRetainsDeclarationAndBindsFollowingReference() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        annotation class Suppress(val name: String)
        class Foo(val number: Int, val text: String)
        fun probe() {
            val foo = @Suppress("X") Foo(42, "OK")
            foo.number
        }
        """.utf8))
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let localIndex = try #require(ast.arena.exprs.indices.first { index in
            guard case let .localDecl(name, _, _, _, _, _, _) = ast.arena.exprs[index] else { return false }
            return ctx.interner.resolve(name) == "foo"
        })
        guard case let .localDecl(_, _, _, initializer?, _, _, _) = ast.arena.exprs[localIndex],
              case let .call(callee, _, arguments, _) = ast.arena.expr(initializer),
              case let .nameRef(calleeName, _) = ast.arena.expr(callee) else {
            Issue.record("Expected the annotated constructor call in the local initializer")
            return
        }
        #expect(ctx.interner.resolve(calleeName) == "Foo")
        #expect(arguments.count == 2)
        #expect(ast.arena.expressionAnnotations(for: initializer).map(\.name) == ["Suppress"])

        let referenceIndex = try #require(ast.arena.exprs.indices.first { index in
            guard case let .nameRef(name, _) = ast.arena.exprs[index] else { return false }
            return ctx.interner.resolve(name) == "foo"
        })
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(referenceIndex))) != nil)
    }

    @Test
    func expressionBodyRetainsCallAndAnnotationAcrossSnapshot() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Bag {
         fun add(x: Int): Int = x
         fun adding(x: Int): Int = @Suppress("DEPRECATION") add(x)
        }
        fun main() {}
        """, includeStdlib: false)
        let function = try #require(ast.arena.decls.compactMap { decl -> FunDecl? in
            guard case let .funDecl(value) = decl,
                  ctx.interner.resolve(value.name) == "adding" else { return nil }
            return value
        }.first)
        guard case let .expr(body, _) = function.body else {
            Issue.record("Expression body was lost")
            return
        }
        guard case let .call(callee, _, arguments, _) = ast.arena.expr(body),
              case let .nameRef(name, _) = ast.arena.expr(callee) else {
            Issue.record("Expected the original operand call")
            return
        }
        #expect(ctx.interner.resolve(name) == "add")
        #expect(arguments.count == 1)
        #expect(ast.arena.expressionAnnotations(for: body).map(\.name) == ["Suppress"])
        let data = try JSONEncoder().encode(ast.arena.snapshot())
        let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: data))
        #expect(restored.expressionAnnotations(for: body) == ast.arena.expressionAnnotations(for: body))
    }

    @Test
    func annotatedWhenBlockRetainsBranchesAndTrailingValue() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun choose(flag: Boolean): Int = when {
         flag -> @Suppress("UNUSED_VARIABLE") {
          val value = 7
          value
         }
         else -> 9
        }
        fun main() {}
        """, includeStdlib: false)
        let function = try #require(firstFunDecl(named: "choose", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body,
              case let .whenExpr(_, branches, elseExpr, _) = ast.arena.expr(body) else {
            Issue.record("Expected when expression")
            return
        }
        #expect(branches.count == 1)
        let branch = try #require(branches.first)
        guard case let .blockExpr(statements, trailing, _) = ast.arena.expr(branch.body) else {
            Issue.record("Annotated braces must retain block semantics")
            return
        }
        #expect(statements.count == 1)
        #expect(trailing != nil)
        #expect(ast.arena.expressionAnnotations(for: branch.body).map(\.name) == ["Suppress"])
        #expect(ast.arena.expressionAnnotations(for: try #require(elseExpr)).isEmpty)
    }

    @Test
    func prefixesPreserveUnaryPrecedenceQualifiedNamesAndLambdaBranches() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun unary(): Int = @kotlin.Suppress("A") @Suppress("B") -7 + 9
        fun lambda(flag: Boolean): (Int) -> Int = when {
            flag -> @Suppress("UNUSED_PARAMETER") { x -> x + 1 }
            else -> { x -> x - 1 }
        }
        """, includeStdlib: false)
        let unary = try #require(firstFunDecl(named: "unary", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = unary.body,
              case let .binary(_, lhs, _, _) = ast.arena.expr(body) else {
            Issue.record("Annotation must not absorb the binary expression")
            return
        }
        #expect(ast.arena.expressionAnnotations(for: lhs).map(\.name) == ["kotlin.Suppress", "Suppress"])
        let lambda = try #require(firstFunDecl(named: "lambda", in: ast, interner: ctx.interner))
        guard case let .expr(lambdaBody, _) = lambda.body,
              case let .whenExpr(_, branches, elseExpr, _) = ast.arena.expr(lambdaBody) else {
            Issue.record("Expected when expression")
            return
        }
        for branch in branches.map(\.body) + [try #require(elseExpr)] {
            guard case .lambdaLiteral = ast.arena.expr(branch) else {
                Issue.record("Arrow-bearing braces must remain lambdas")
                continue
            }
        }
    }

    @Test
    func annotatedControlBodiesAndPostfixOperandsRetainTheirShapes() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun branches(flag: Boolean): Int = if (flag) @Suppress("UNUSED") { 3 } else @Suppress("UNUSED") { 4 }
        fun invoked(flag: Boolean): Int = when {
            flag -> @Suppress("UNUSED") ({ x: Int -> x + 1 })(2)
            else -> ({ x: Int -> x - 1 })(2)
        }
        fun indexed(values: List<Int>): Int = @Suppress("UNUSED") values[0]
        fun member(value: String?): Int = @Suppress("UNUSED") value!!.length
        fun innerUnary(): Int = -@Suppress("UNUSED") 7
        fun innerIncrement(value: Int): Int = ++@Suppress("UNUSED") value
        fun outerIncrement(value: Int): Int = @Suppress("UNUSED") ++value
        """, includeStdlib: false)
        func body(_ name: String) throws -> ExprID {
            let function = try #require(firstFunDecl(named: name, in: ast, interner: ctx.interner))
            guard case let .expr(expr, _) = function.body else {
                Issue.record("Missing expression body for \(name)")
                throw CancellationError()
            }
            return expr
        }
        guard case let .ifExpr(_, thenExpr, elseExpr, _) = ast.arena.expr(try body("branches")) else {
            Issue.record("Expected if expression")
            return
        }
        for expr in [thenExpr, try #require(elseExpr)] {
            guard case .blockExpr = ast.arena.expr(expr) else {
                Issue.record("Expected annotated block")
                continue
            }
            #expect(ast.arena.expressionAnnotations(for: expr).map(\.name) == ["Suppress"])
        }
        guard case let .whenExpr(_, branches, fallback, _) = ast.arena.expr(try body("invoked")) else {
            Issue.record("Expected when expression")
            return
        }
        for expr in branches.map(\.body) + [try #require(fallback)] {
            guard case let .call(callee, _, args, _) = ast.arena.expr(expr),
                  case .lambdaLiteral = ast.arena.expr(callee) else {
                Issue.record("Expected invoked lambda, including its postfix arguments")
                continue
            }
            #expect(args.count == 1)
        }
        guard case .indexedAccess = ast.arena.expr(try body("indexed")),
              case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(try body("member")),
              case .nullAssert = ast.arena.expr(receiver),
              case let .unaryExpr(_, operand, _) = ast.arena.expr(try body("innerUnary")),
              case .blockExpr = ast.arena.expr(try body("innerIncrement")) else {
            Issue.record("Annotation changed a postfix/unary operand")
            return
        }
        #expect(ast.arena.expressionAnnotations(for: operand).map(\.name) == ["Suppress"])
        let increment = try body("outerIncrement")
        let range = try #require(ast.arena.exprRange(increment))
        #expect(range.start.offset < range.end.offset)
        #expect(ast.arena.expressionAnnotations(for: increment).map(\.name) == ["Suppress"])
    }

    @Test
    func anonymousFunctionSiteSurvivesSnapshotWithoutMarkingOrdinaryBlocks() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun anonymous(): () -> Int = @FunctionTag fun(): Int { return 7 }
        fun block(flag: Boolean): Int = when { flag -> @ExpressionTag { 7 }; else -> 8 }
        """, includeStdlib: false)
        let function = try #require(firstFunDecl(named: "anonymous", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body else {
            Issue.record("Missing anonymous function operand")
            return
        }
        #expect(ast.arena.isAnonymousFunction(body))
        let restored = ASTArena(snapshot: try JSONDecoder().decode(
            ASTArenaSnapshot.self, from: JSONEncoder().encode(ast.arena.snapshot())
        ))
        #expect(restored.isAnonymousFunction(body))
        #expect(restored.expressionAnnotations(for: body).map(\.name) == ["FunctionTag"])
        let block = try #require(firstFunDecl(named: "block", in: ast, interner: ctx.interner))
        guard case let .expr(whenID, _) = block.body,
              case let .whenExpr(_, branches, _, _) = ast.arena.expr(whenID) else {
            Issue.record("Expected when expression")
            return
        }
        #expect(!restored.isAnonymousFunction(try #require(branches.first).body))
    }
}
