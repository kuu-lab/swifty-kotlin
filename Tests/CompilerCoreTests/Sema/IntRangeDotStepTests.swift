#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IntRangeDotStepTests {
    @Test func dotStepInfersProgressionType() throws {
        let ctx = makeContextFromSource("""
        fun probe(range: IntRange) {
            (1..10).step(3)
            range.step(3)
            (1..10).step(3).step(2)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var calls = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id),
                  callee == KnownCompilerNames(interner: ctx.interner).step
            else { continue }
            let type = try #require(sema.bindings.exprType(for: id))
            let (_, symbol) = try #require(resolveClassTypeSymbol(type, sema: sema))
            #expect(symbol.fqName == ["kotlin", "ranges", "IntProgression"].map(ctx.interner.intern))
            calls += 1
        }
        #expect(calls == 4)
    }
}
#endif
