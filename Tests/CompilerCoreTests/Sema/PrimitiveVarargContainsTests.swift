@testable import CompilerCore
import Testing

@Suite
struct PrimitiveVarargContainsTests {
    @Test
    func primitiveVarargContainsResolvesToBundledSource() throws {
        let source = ["Boolean", "Byte", "Char", "Int", "Long", "Short"].map { type in
            "fun probe\(type)(vararg xs: \(type)) = xs.contains(xs[0])"
        }.joined(separator: "\n")
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var count = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, name, _, _, range) = ast.arena.expr(id),
                      ctx.interner.resolve(name) == "contains",
                      ctx.sourceManager.path(of: range.start.file) == path
                else { continue }
                let binding = try #require(sema.bindings.callBinding(for: id))
                let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "contains"])
                count += 1
            }
            #expect(count == 6)
        }
    }

    @Test
    func floatingArrayContainsReportsSemaError() throws {
        try withTemporaryFile(contents: """
        fun probeFloats(vararg xs: Float) = xs.contains(xs[0])
        fun probeDoubles(vararg xs: Double) = xs.contains(xs[0])
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let rejectionCodes: Set<String> = ["KSWIFTK-SEMA-0024", "KSWIFTK-TYPE-0001"]
            #expect(ctx.diagnostics.hasError)
            #expect(
                ctx.diagnostics.diagnostics.filter { rejectionCodes.contains($0.code) }.count == 2,
                "Expected both floating-array calls to be rejected: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func userPrimitiveArrayContainsExtensionTakesPrecedence() throws {
        try withTemporaryFile(contents: """
        fun IntArray.contains(element: Int): Boolean = false
        fun DoubleArray.contains(element: Double): Boolean = this.size > 0
        fun probeInts(vararg xs: Int) = xs.contains(1)
        fun probeDoubles(vararg xs: Double) = xs.contains(1.0)
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var count = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, name, _, _, range) = ast.arena.expr(id),
                      ctx.interner.resolve(name) == "contains",
                      ctx.sourceManager.path(of: range.start.file) == path
                else { continue }
                let binding = try #require(sema.bindings.callBinding(for: id))
                let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["contains"])
                count += 1
            }
            #expect(count == 2)
        }
    }
}
