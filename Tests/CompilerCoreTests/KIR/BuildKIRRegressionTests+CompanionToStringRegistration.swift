#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    /// KUU-2935: a companion object that overrides `toString()` must register
    /// its Any-erased bridge (`kk_object_register_any_to_string`) from the
    /// eager `__companion_init_*` initializer — the same registration
    /// `synthesizeObjectInitializer` performs for named objects. Without it,
    /// `Companion`-typed values stringified through `Any` fall back to
    /// `<object 0x...>`.
    @Test func companionToStringOverrideRegistersAnyErasedBridge() throws {
        let ctx = makeContextFromSource("""
        object Named {
            override fun toString(): String = "named"
        }
        class Outer {
            private companion object {
                override fun toString(): String = "OK"
            }
            class Nested { fun foo(): Any = Outer.Companion }
            fun test() = Nested().foo().toString()
        }
        fun main() { println(Outer().test()) }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics.map(\.code))")

        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        func registersAnyToStringBridge(_ function: KIRFunction) -> Bool {
            function.body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "kk_object_register_any_to_string"
            }
        }
        // Control: named objects have always emitted the registration.
        let objectInit = try #require(functions.first { function in
            ctx.interner.resolve(function.name).hasPrefix("__object_init_")
        })
        #expect(registersAnyToStringBridge(objectInit))
        let companionInit = try #require(functions.first { function in
            ctx.interner.resolve(function.name).hasPrefix("__companion_init_")
        })
        #expect(registersAnyToStringBridge(companionInit))
    }
}
#endif
