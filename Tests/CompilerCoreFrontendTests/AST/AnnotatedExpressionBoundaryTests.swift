@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnnotatedExpressionBoundaryTests {
    @Test(arguments: ["\n", "\n// operand prefix\n"])
    func newlineAfterEqualsRetainsTheUpstreamCall(separator: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Bag {
            fun add(x: Int): Int = x
            fun adding(x: Int): Int =\(separator) @Suppress("DEPRECATION") add(x)
            @HeaderTag fun after(): Int = 9
        }
        fun main() {}
        """, includeStdlib: false)
        let functions = ast.arena.decls.compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration else { return nil }
            return function
        }
        let adding = try #require(functions.first { ctx.interner.resolve($0.name) == "adding" })
        guard case let .expr(body, _) = adding.body,
              case let .call(callee, _, args, _) = ast.arena.expr(body),
              case let .nameRef(name, _) = ast.arena.expr(callee) else {
            Issue.record("Newline annotation must not end the function body")
            return
        }
        #expect(ctx.interner.resolve(name) == "add")
        #expect(args.count == 1)
        #expect(ast.arena.expressionAnnotations(for: body).map(\.name) == ["Suppress"])
        #expect(functions.contains { ctx.interner.resolve($0.name) == "after" && $0.annotations.map(\.name) == ["HeaderTag"] })
    }

    @Test
    func prefixesAndOperandMayBeOnSeparateLines() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun value(): Int =
            @kotlin.Suppress("UNUSED")
            @SecondTag
            -7 + 9
        @HeaderTag fun after(): Int = 5
        """, includeStdlib: false)
        let function = try #require(firstFunDecl(named: "value", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body,
              case let .binary(_, lhs, _, _) = ast.arena.expr(body) else {
            Issue.record("Expected the complete annotated unary operand")
            return
        }
        #expect(ast.arena.expressionAnnotations(for: lhs).map(\.name) == ["kotlin.Suppress", "SecondTag"])
        let after = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
        #expect(after.annotations.map(\.name) == ["HeaderTag"])
    }

    @Test
    func missingOperandStillRecoversAtAnAnnotatedDeclaration() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun missing(): Int =
        @HeaderTag fun after(): Int = 7
        """, includeStdlib: false)
        let after = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
        #expect(after.annotations.map(\.name) == ["HeaderTag"])
        guard case let .expr(body, _) = after.body, case .intLiteral(7, _) = ast.arena.expr(body) else {
            Issue.record("Recovery must retain the next declaration's body")
            return
        }
    }

    @Test
    func annotatedAnonymousFunctionMayStartOnTheNextLine() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun make(): () -> Int =
            @FunctionTag
            fun(): Int { return 7 }
        fun after(): Int = 9
        """, includeStdlib: false)
        let function = try #require(firstFunDecl(named: "make", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body else {
            Issue.record("Missing anonymous function operand")
            return
        }
        #expect(ast.arena.isAnonymousFunction(body))
        #expect(ast.arena.expressionAnnotations(for: body).map(\.name) == ["FunctionTag"])
        #expect(firstFunDecl(named: "after", in: ast, interner: ctx.interner) != nil)
    }
    @Test
    func unclosedAnnotationArgumentsRecoverAtTheNextDeclaration() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun broken() =
            @Suppress("UNUSED"
        fun after(): Int = 7
        """, includeStdlib: false)
        let after = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = after.body, case .intLiteral(7, _) = ast.arena.expr(body) else {
            Issue.record("An unclosed annotation must not consume the next function")
            return
        }
    }


    @Test
    func multilineNamedAnnotationArgumentIsNotADeclarationModifier() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun value(): Int =
            @Tag(
                value = 1
            ) 7
        fun after(): Int = 9
        """, includeStdlib: false)
        let function = try #require(firstFunDecl(named: "value", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body, case .intLiteral(7, _) = ast.arena.expr(body) else {
            Issue.record("Named annotation arguments must retain the expression operand")
            return
        }
        #expect(ast.arena.expressionAnnotations(for: body).map(\.name) == ["Tag"])
        #expect(firstFunDecl(named: "after", in: ast, interner: ctx.interner) != nil)
    }

    @Test
    func multilineClassLiteralArgumentPreservesDeclarationAndExpressionAnnotations() throws {
        let (ast, ctx) = try buildASTModule(from: """
        @Tag(Int::
            class)
        fun header(): Int = 1
        fun value(): Int =
            @Tag(Int::
                class) 7
        fun after(): Int = 9
        """, includeStdlib: false)
        let header = try #require(firstFunDecl(named: "header", in: ast, interner: ctx.interner))
        #expect(header.annotations.map(\.name) == ["Tag"])
        let function = try #require(firstFunDecl(named: "value", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body, case .intLiteral(7, _) = ast.arena.expr(body) else {
            Issue.record("KClass literal arguments must not end expression annotations")
            return
        }
        #expect(ast.arena.expressionAnnotations(for: body).map(\.name) == ["Tag"])
        #expect(firstFunDecl(named: "after", in: ast, interner: ctx.interner) != nil)
    }

}
