#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    /// KUU-3210: a value parameter sharing the local function's own name
    /// shadows it in value position — `a` in `fun a(a: Any) = a === 1.1`
    /// binds to the parameter, not the function (JetBrains kt36952).
    @Test
    func localFunctionParameterShadowsFunctionNameInValuePosition() throws {
        let ctx = makeContextFromSource("""
        fun box(): String {
            fun a(a: Any) = a === 1.1 is Double
            return if (a(true)) "OK" else "Fail"
        }
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let aName = ctx.interner.intern("a")
        let aFunSymbol = try #require(ast.arena.exprs.indices.compactMap { index -> SymbolID? in
            guard case let .localFunDecl(name, _, _, _, _, _, _, _, _) = ast.arena.exprs[index],
                  name == aName
            else {
                return nil
            }
            return sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))]
        }.first)
        let aParamSymbol = try #require(
            sema.symbols.functionSignature(for: aFunSymbol)?.valueParameterSymbols.first
        )
        // The `a === 1.1` operand binds to the parameter, not the function.
        let parameterBoundRefs = ast.arena.exprs.indices.filter { index in
            guard case let .nameRef(name, _) = ast.arena.exprs[index],
                  name == aName
            else {
                return false
            }
            return sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))] == aParamSymbol
        }
        #expect(parameterBoundRefs.count == 1)
        // The `a(true)` call still resolves to the function itself.
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == aFunSymbol })
    }

    /// KUU-3210: a function-typed parameter sharing the local function's own
    /// name also shadows it in call position — `f()` in
    /// `fun f(f: () -> String) = f()` invokes the parameter, matching kotlinc.
    @Test
    func localFunctionParameterShadowsFunctionNameInCallPosition() throws {
        let ctx = makeContextFromSource("""
        fun apply(): String {
            fun f(f: () -> String) = f()
            return f({ "OK" })
        }
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let fName = ctx.interner.intern("f")
        let fFunSymbol = try #require(ast.arena.exprs.indices.compactMap { index -> SymbolID? in
            guard case let .localFunDecl(name, _, _, _, _, _, _, _, _) = ast.arena.exprs[index],
                  name == fName
            else {
                return nil
            }
            return sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))]
        }.first)
        let fParamSymbol = try #require(
            sema.symbols.functionSignature(for: fFunSymbol)?.valueParameterSymbols.first
        )
        // The inner `f()` callee binds to the parameter; only the outer
        // `f({ "OK" })` call chooses the function itself.
        let parameterBoundRefs = ast.arena.exprs.indices.filter { index in
            guard case let .nameRef(name, _) = ast.arena.exprs[index],
                  name == fName
            else {
                return false
            }
            return sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))] == fParamSymbol
        }
        #expect(parameterBoundRefs.count == 1)
        #expect(sema.bindings.callBindings.values.filter { $0.chosenCallee == fFunSymbol }.count == 1)
    }

    /// KUU-3210: the function's own name stays reachable through the lexical
    /// scope, so ordinary recursion in the body still resolves.
    @Test
    func localFunctionRecursionStillResolvesThroughScope() throws {
        let ctx = makeContextFromSource("""
        fun countdown(n: Int): Int {
            fun cd(k: Int): Int = if (k <= 0) 0 else cd(k - 1)
            return cd(n)
        }
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let cdName = ctx.interner.intern("cd")
        let cdSymbol = try #require(ast.arena.exprs.indices.compactMap { index -> SymbolID? in
            guard case let .localFunDecl(name, _, _, _, _, _, _, _, _) = ast.arena.exprs[index],
                  name == cdName
            else {
                return nil
            }
            return sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))]
        }.first)
        // Both `cd(n)` and the recursive `cd(k - 1)` choose the local function.
        let cdCalls = sema.bindings.callBindings.values.filter { $0.chosenCallee == cdSymbol }
        #expect(cdCalls.count == 2)
    }
}
#endif
