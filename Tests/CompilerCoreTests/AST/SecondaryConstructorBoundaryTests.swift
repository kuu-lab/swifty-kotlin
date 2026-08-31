#if canImport(Testing)
@testable import CompilerCore
import Testing

// BUG-227: an annotated secondary constructor placed after a `;`-terminated
// statement on the same physical line (e.g. `val y = 1; @Anno constructor() : this(0)`)
// used to be dropped from the AST entirely, because the parser's block-level
// declaration gate only recognized a leading newline or block-start as a
// fresh statement boundary — not an explicit `;` separator. See
// Tests/CompilerCoreTests/Parser/DeclarationBoundaryTests.swift for the
// parser/CST-level regression coverage of the same fix.
@Suite("SecondaryConstructorBoundary")
struct SecondaryConstructorBoundaryTests {

    private func buildAST(_ source: String) throws -> (ASTModule, CompilationContext) {
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        let ast = try #require(ctx.ast)
        return (ast, ctx)
    }

    private func classDecl(named name: String, in ast: ASTModule, ctx: CompilationContext) throws -> ClassDecl {
        let classes = ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case .classDecl(let cls) = decl else { return nil }
            return cls
        }
        return try #require(classes.first { ctx.interner.resolve($0.name) == name })
    }

    @Test
    func testAnnotatedSecondaryConstructorAfterSemicolonPreservesAnnotationAndDelegation() throws {
        let (ast, ctx) = try buildAST("""
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class CtorOnly

        class Foo(val x: Int) { val y = 1; @CtorOnly constructor() : this(0) }
        """)

        #expect(!ctx.diagnostics.hasError)

        let cls = try classDecl(named: "Foo", in: ast, ctx: ctx)
        #expect(cls.secondaryConstructors.count == 1)

        let ctor = try #require(cls.secondaryConstructors.first)
        #expect(ctor.annotations.map(\.name) == ["CtorOnly"])
        #expect(ctor.delegationCall != nil)
        #expect(ctor.delegationCall?.kind == .this)
    }

    @Test
    func testAnnotatedSecondaryConstructorOnOwnLineStillWorks() throws {
        let (ast, ctx) = try buildAST("""
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class CtorOnly

        class Foo(val x: Int) {
            @CtorOnly
            constructor() : this(0)
        }
        """)

        #expect(!ctx.diagnostics.hasError)

        let cls = try classDecl(named: "Foo", in: ast, ctx: ctx)
        #expect(cls.secondaryConstructors.count == 1)

        let ctor = try #require(cls.secondaryConstructors.first)
        #expect(ctor.annotations.map(\.name) == ["CtorOnly"])
        #expect(ctor.delegationCall != nil)
    }

    @Test
    func testTwoAnnotatedSecondaryConstructorsPackedOnOneLine() throws {
        let (ast, ctx) = try buildAST("""
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class First
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class Second

        class Foo(val x: Int) { @First constructor(a: Int) : this(a); @Second constructor() : this(0) }
        """)

        #expect(!ctx.diagnostics.hasError)

        let cls = try classDecl(named: "Foo", in: ast, ctx: ctx)
        #expect(cls.secondaryConstructors.count == 2)
        #expect(cls.secondaryConstructors.map { $0.annotations.map(\.name) } == [["First"], ["Second"]])
    }
}
#endif
