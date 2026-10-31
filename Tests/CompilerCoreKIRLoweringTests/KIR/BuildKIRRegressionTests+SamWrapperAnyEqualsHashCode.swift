#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// KUU-3865: a `fun interface` whose only abstract member is a declared
    /// `Any.equals`/`Any.hashCode` produces a SAM wrapper whose synthesized
    /// method must be registered on the per-object erased-Any override
    /// tables (`kk_object_register_equals_override` /
    /// `kk_object_register_hashcode_override`) — not only through the
    /// interface itable — or calls erased through `Any` fall back to
    /// identity semantics.
    @Test func samWrapperEqualsHashCodeRegisterErasedOverrides() throws {
        let ctx = makeContextFromSource("""
        fun interface E {
            override fun equals(other: Any?): Boolean
        }
        fun interface H {
            override fun hashCode(): Int
        }
        fun main() {
            val e = E { it -> it == null }
            val h = H { 42 }
            val a: Any = e
            val b: Any = h
            println(a.equals(e))
            println(b.hashCode())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics.map(\.code))")

        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

        var symbolConstants: [KIRExprID: SymbolID] = [:]
        for instruction in mainBody {
            if case let .constValue(result, .symbolRef(symbol)) = instruction {
                symbolConstants[result] = symbol
            }
        }
        for registerCallee in ["kk_object_register_equals_override", "kk_object_register_hashcode_override"] {
            let registration = try #require(mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == registerCallee
            }, "the SAM wrapper object must register its erased-Any \(registerCallee) override")
            guard case let .call(_, _, arguments, _, _, _, _, _) = registration,
                  arguments.count == 2,
                  let methodSymbol = symbolConstants[arguments[1]],
                  let owner = sema.symbols.parentSymbol(for: methodSymbol),
                  let ownerInfo = sema.symbols.symbol(owner)
            else {
                Issue.record("\(registerCallee) must take the wrapper method symbol")
                continue
            }
            #expect(
                ctx.interner.resolve(ownerInfo.name).hasPrefix("kk_sam_wrapper_"),
                "the registered \(registerCallee) argument must be the synthesized SAM wrapper method, got owner \(ctx.interner.resolve(ownerInfo.name))"
            )
        }
    }

    /// A SAM that is not an `Any` member must never occupy the erased-Any
    /// equals/hashCode slots — an `invoke`-SAM wrapper registers nothing.
    @Test func nonAnySamWrapperDoesNotRegisterErasedEqualsHashCode() throws {
        let ctx = makeContextFromSource("""
        fun interface F {
            fun invoke(): Int
        }
        fun main() {
            val f = F { 1 }
            println(f.invoke())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics.map(\.code))")

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        #expect(!mainBody.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            let name = ctx.interner.resolve(callee)
            return name == "kk_object_register_equals_override" || name == "kk_object_register_hashcode_override"
        }, "non-Any SAMs must not occupy the erased-Any equals/hashCode slots")
    }
}
#endif
