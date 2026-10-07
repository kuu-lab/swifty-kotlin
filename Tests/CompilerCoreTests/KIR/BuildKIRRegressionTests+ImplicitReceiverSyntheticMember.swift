#if canImport(Testing)
@testable import CompilerCore
import Testing

// KUU-1451 regression: a bare `lastIndex`/`indices` read on a scope-function
// implicit receiver must lower to the zero-argument extension-function call
// on `this`, not `symbolRef` of the raw function symbol — boxing the callee
// address as Int printed garbage and reading it back as IntRange panicked.
// A member function in the same position keeps virtual dispatch (`c.m`).
extension BuildKIRRegressionTests {
    @Test func testImplicitReceiverSyntheticMemberPropertyLowersToReceiverCall() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val l = listOf(1, 2, 3)
            println(l.run { lastIndex })
            with(l) { println(indices) }
        }
        """)
        try runToKIR(ctx)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let collections = [ctx.interner.intern("kotlin"), ctx.interner.intern("collections")]
        let functions = findAllKIRFunctions(in: module)
        for member in ["lastIndex", "indices"] {
            let memberSymbols = sema.symbols.lookupAll(fqName: collections + [ctx.interner.intern(member)])
            #expect(!memberSymbols.isEmpty, "expected kotlin.collections.\(member) symbols")
            #expect(functions.contains { function in
                function.body.contains { instruction in
                    guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction else { return false }
                    return arguments.count == 1 && symbol.map { memberSymbols.contains($0) } == true
                }
            }, "expected a one-argument call to kotlin.collections.\(member) with the implicit receiver")
            #expect(!functions.contains { function in
                function.body.contains { instruction in
                    guard case let .constValue(_, value) = instruction,
                          case let .symbolRef(symbol) = value
                    else { return false }
                    return memberSymbols.contains(symbol)
                }
            }, "\(member) must not lower to a raw symbolRef of the function")
        }
    }

    @Test func testImplicitReceiverMemberFunctionKeepsVirtualDispatch() throws {
        let ctx = makeContextFromSource("""
        open class Base { open fun describe(): Int = 10 }
        class Derived : Base() { override fun describe(): Int = 20 }

        fun probe(b: Base): Int = b.run { describe }
        """)
        try runToKIR(ctx)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let describeSymbol = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("Base"),
            ctx.interner.intern("describe"),
        ]).first { symbol in
            sema.symbols.symbol(symbol)?.kind == .function
        })
        let lambdas = findAllKIRFunctions(in: module).filter {
            ctx.interner.resolve($0.name).hasPrefix("kk_lambda")
        }
        #expect(lambdas.contains { function in
            function.body.contains { instruction in
                guard case let .virtualCall(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == describeSymbol
            }
        }, "bare `describe` on the implicit receiver must keep vtable dispatch")
    }
}
#endif
