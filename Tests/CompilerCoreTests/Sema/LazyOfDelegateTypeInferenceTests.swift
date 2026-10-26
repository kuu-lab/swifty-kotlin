#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LazyOfDelegateTypeInferenceTests {

    @Test
    func infersValueTypeFromLazyOfForLocalDelegate() throws {
        let ctx = makeContextFromSource("""
            fun main() {
                val l by lazyOf(7)
                println(l)
            }
            """)

        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.allSatisfy { $0.severity != .error })
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let mainBody = try #require(ast.files.lazy.compactMap { file -> [ExprID]? in
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      ctx.interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
            return nil
        }.first)

        let declaration = try #require(mainBody.first { exprID in
            guard case let .localDecl(name, _, _, _, isDelegated, _, _) = ast.arena.expr(exprID) else {
                return false
            }
            return ctx.interner.resolve(name) == "l" && isDelegated
        })
        let symbol = try #require(sema.bindings.identifierSymbol(for: declaration))
        #expect(sema.symbols.propertyType(for: symbol) == sema.types.intType)
    }
}

#endif
