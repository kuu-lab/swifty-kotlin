#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TopLevelPropertySmartCastMemberCallTests {
    @Test
    func immutableTopLevelPropertyNarrowsAndMaterializesForMemberCalls() throws {
        let source = """
        fun initial(): Any = 'A'
        val G: Any = initial()
        val Char.code: Int get() = 65
        fun Char.toInt(): Int = 65
        fun probe(): Int {
            if (G is Char) return G.code + G.toInt()
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let global = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("G")]))
            let globalLoads = Set(body.compactMap { instruction -> KIRExprID? in
                guard case let .loadGlobal(result, symbol) = instruction, symbol == global else { return nil }
                return result
            })
            #expect(!globalLoads.isEmpty, "Expected probe to read the G global")
            #expect(body.contains { instruction in
                guard case let .copy(from, to) = instruction, globalLoads.contains(from) else { return false }
                return module.arena.exprType(from) == sema.types.anyType
                    && module.arena.exprType(to) == sema.types.charType
            })
        }
    }

    @Test
    func mutableTopLevelPropertyRemainsUnstable() throws {
        let source = """
        var G: Any = 'A'
        val Char.code: Int get() = 65
        fun probe(): Int {
            if (G is Char) return G.code
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "A mutable top-level property must not be smartcast: \(ctx.diagnostics.diagnostics)")
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" },
                "Expected unresolved-member diagnostic for the unstable property, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )
        }
    }
}
#endif
