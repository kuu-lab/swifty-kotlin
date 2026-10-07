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

    /// Kotlin requires invocation syntax for functions (`m()`), so a bare
    /// user-declared extension function on the implicit receiver must not be
    /// invoked through the property-style path — only bundled stdlib
    /// declarations participate in that facade. The name falls back to a raw
    /// `symbolRef` (the pre-existing behavior for unresolved property-style
    /// reads; real kotlinc rejects this program outright).
    @Test func testImplicitReceiverUserExtensionFunctionIsNotInvoked() throws {
        let ctx = makeContextFromSource("""
        fun <T> List<T>.myProp(): Int = 99

        fun main() {
            val l = listOf(1, 2, 3)
            println(l.run { myProp })
        }
        """)
        try runToKIR(ctx)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let myPropSymbol = try #require(sema.symbols.lookupByShortName(
            ctx.interner.intern("myProp")
        ).first { symbol in
            sema.symbols.symbol(symbol)?.kind == .function
        })
        let functions = findAllKIRFunctions(in: module)
        #expect(!functions.contains { function in
            function.body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == myPropSymbol
            }
        }, "user-declared extension functions must not be invoked property-style")
        #expect(!functions.contains { function in
            function.body.contains { instruction in
                guard case let .virtualCall(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == myPropSymbol
            }
        })
    }
}
#endif
