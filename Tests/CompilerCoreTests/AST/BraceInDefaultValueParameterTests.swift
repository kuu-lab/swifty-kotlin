#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for value parameters whose default value expression
/// contains a `{`, e.g. a scope-function call (`run { ... }`) or a lambda
/// literal (`{ ... }`) used directly as the default. `declarationValueParameters`
/// (BuildASTPhase+DeclBuilders.swift) used to break out of its parameter-scanning
/// loop on ANY `{` token, regardless of nesting depth, mistaking the default
/// value's brace for the start of the function body. That silently truncated
/// the parameter list before its closing `)`, dropping the parameter under
/// scan and any parameters declared after it.
@Suite
struct BraceInDefaultValueParameterTests {
    private func buildAST(from source: String) throws -> (ASTModule, CompilationContext) {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(ctx)
        return (try #require(ctx.ast), ctx)
    }

    private func firstFunDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> FunDecl? {
        ast.arena.declarations().compactMap { decl -> FunDecl? in
            guard case let .funDecl(funDecl) = decl else { return nil }
            return funDecl
        }.first { interner.resolve($0.name) == name }
    }

    @Test
    func testScopeFunctionDefaultValueDoesNotTruncateParameterList() throws {
        let source = """
        package demo
        fun f(x: Int = run { 5 }): Int = x
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "f", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["x"])
        #expect(funDecl.valueParams.first?.hasDefaultValue == true)
    }

    @Test
    func testLambdaLiteralDefaultValueDoesNotTruncateParameterList() throws {
        let source = """
        package demo
        fun g(action: () -> Int = { 42 }): Int = action()
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "g", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["action"])
        #expect(funDecl.valueParams.first?.hasDefaultValue == true)
    }

    @Test
    func testParameterAfterBraceContainingDefaultIsNotDropped() throws {
        let source = """
        package demo
        fun h(x: Int = run { 1 }, y: Int = 2): Int = x + y
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "h", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["x", "y"])
        #expect(funDecl.valueParams.allSatisfy { $0.hasDefaultValue })
    }
}
#endif
