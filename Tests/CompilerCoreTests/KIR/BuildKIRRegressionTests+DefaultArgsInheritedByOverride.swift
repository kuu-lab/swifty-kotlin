#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-655: KIR-level counterpart of `OverrideDefaultArgumentInheritanceTests`.
/// An override that inherits its defaults never gets a `$default` stub of
/// its own (its AST has no default value expressions to evaluate) -- call
/// sites must route through the base declaration's stub instead
/// (`CallSupportLowerer.defaultStubOwnerSymbol`), and that stub's own inner
/// call must dispatch virtually so a base-typed receiver still reaches the
/// runtime type's override (see the virtual-dispatch attempt in
/// `CallSupportLowerer.generateDefaultStubFunction`).
extension BuildKIRRegressionTests {
    @Test
    func classOverrideOmittedArgumentRoutesThroughBaseStubOnly() throws {
        let source = """
        open class A { open fun f(x: Int = 1) = "A$x" }
        class B : A() { override fun f(x: Int) = "B$x" }
        fun probe(): String {
            val a: A = B()
            return a.f() + B().f()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let functions = findAllKIRFunctions(in: module)
        let stubSymbols = Set(functions.filter { $0.name == ctx.interner.intern("f") }
            .map { SyntheticSymbolScheme.defaultStubSymbol(for: $0.symbol) })
        let defaultStubs = functions.filter { stubSymbols.contains($0.symbol) }
        #expect(defaultStubs.count == 1, "Expected exactly one f$default stub (owned by A.f), got: \(defaultStubs.count)")

        let sema = try #require(ctx.sema)
        let aF = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("A"), ctx.interner.intern("f")]).first)
        if let stub = defaultStubs.first {
            #expect(stub.symbol == SyntheticSymbolScheme.defaultStubSymbol(for: aF))
        }

        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let baseStub = SyntheticSymbolScheme.defaultStubSymbol(for: aF)
        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == baseStub
        }, "Expected probe() to call the base declaration's default stub")
    }

    @Test
    func interfaceOverrideOmittedArgumentGetsADefaultStub() throws {
        let source = """
        interface I { fun m(x: Int = 5): String }
        class IC : I { override fun m(x: Int) = "IC$x" }
        fun probe(): String {
            val i: I = IC()
            return i.m() + IC().m()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        // Before KUU-655, `CallSupportLowerer.collectFunctionDefaults` had no
        // `.interfaceDecl` case at all, so `I.m`'s own default value
        // expression was never collected and no `m$default` stub was ever
        // generated -- every call through it failed at link time with an
        // undefined `_m$default` symbol.
        let functions = findAllKIRFunctions(in: module)
        let stubSymbols = Set(functions.filter { $0.name == ctx.interner.intern("m") }
            .map { SyntheticSymbolScheme.defaultStubSymbol(for: $0.symbol) })
        let defaultStubs = functions.filter { stubSymbols.contains($0.symbol) }
        #expect(defaultStubs.count == 1, "Expected exactly one m$default stub (owned by I.m), got: \(defaultStubs.count)")

        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let stub = try #require(defaultStubs.first)
        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == stub.symbol
        })
    }
}
#endif
