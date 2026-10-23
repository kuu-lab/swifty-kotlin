#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LocalFunctionValueNameCollisionTests {
    /// KUU-2193: a same-named value remains visible as an argument while
    /// call-position lookup considers every local function overload.
    @Test
    func sameNamedValueAndLocalFunctionUseSeparateCallAndValueLookups() throws {
        let ctx = makeContextFromSource("""
        fun probe(): String {
            var s = ""
            var foo = "O"
            fun foo(value: String) { s += value }
            fun foo() { foo("K") }
            foo(foo)
            foo()
            return s
        }
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let fooSymbols = ast.arena.exprs.indices.compactMap { index -> SymbolID? in
            guard case let .localFunDecl(name, _, _, _, _, _, _, _, _) = ast.arena.exprs[index],
                  name == ctx.interner.intern("foo")
            else {
                return nil
            }
            return sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))]
        }
        #expect(fooSymbols.count == 2)

        let fooCalls = sema.bindings.callBindings.values.filter { fooSymbols.contains($0.chosenCallee) }
        #expect(fooCalls.count == 3)
        let callsByArity = Dictionary(grouping: fooCalls) { binding in
            sema.symbols.functionSignature(for: binding.chosenCallee)?.parameterTypes.count ?? -1
        }
        #expect(callsByArity[0]?.count == 1)
        #expect(callsByArity[1]?.count == 2)
    }
}
#endif
