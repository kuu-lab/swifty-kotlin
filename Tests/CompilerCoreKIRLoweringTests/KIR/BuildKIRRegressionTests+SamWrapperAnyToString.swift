#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// KUU-3824 / KT-83308: a `fun interface` whose only abstract member is a
    /// declared `Any.toString` produces a SAM wrapper whose `toString` must be
    /// registered on the per-object erased-Any dispatch table
    /// (`kk_object_register_any_to_string`) — not only through the interface
    /// itable — or calls erased through `Any` render the default object
    /// `toString` (`kk_sam_wrapper_class$SomeFun@hash`).
    @Test func samWrapperToStringRegistersAnyErasedBridge() throws {
        let ctx = makeContextFromSource("""
        fun interface SomeFun {
            override fun toString(): String
        }
        fun main() {
            val o = SomeFun { "O" }
            println(o.toString())
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
        let registration = try #require(mainBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == "kk_object_register_any_to_string"
        }, "the SAM wrapper object must register its Any-erased toString bridge")
        guard case let .call(_, _, arguments, _, _, _, _, _) = registration,
              arguments.count == 2,
              let bridgeSymbol = symbolConstants[arguments[1]]
        else {
            Issue.record("kk_object_register_any_to_string must take a bridge symbol argument")
            return
        }
        let bridge = try #require(
            module.arena.function(for: bridgeSymbol),
            "the registered toString argument must be a generated bridge function"
        )
        #expect(ctx.interner.resolve(bridge.name).hasPrefix("kk_any_to_string_bridge_"))
        let implCall = try #require(bridge.body.first { instruction in
            guard case .call = instruction else { return false }
            return true
        }, "the bridge must forward to the SAM wrapper toString implementation")
        guard case let .call(implSymbol, _, _, _, _, _, _, _) = implCall,
              let implSymbol,
              let owner = sema.symbols.parentSymbol(for: implSymbol),
              let ownerInfo = sema.symbols.symbol(owner)
        else {
            Issue.record("the bridge call must carry the wrapper toString symbol")
            return
        }
        #expect(
            ctx.interner.resolve(ownerInfo.name).hasPrefix("kk_sam_wrapper_"),
            "the bridge must call the synthesized SAM wrapper toString, got owner \(ctx.interner.resolve(ownerInfo.name))"
        )
    }

    /// A member-extension `toString` is not an `Any.toString` override — it is
    /// callable only inside its owner with an explicit extension receiver —
    /// so it must never be registered on the erased-Any dispatch table. The
    /// erased bridge passes only the instance receiver; registering an
    /// extension left its extension-receiver argument unbound and segfaulted
    /// the erased call (KUU-3824).
    @Test func memberExtensionToStringDoesNotRegisterAnyErasedBridge() throws {
        let ctx = makeContextFromSource("""
        class C { fun Int.toString() = "ext" }
        fun interface F { fun Int.toString(): String }
        fun main() {
            val c: Any = C()
            val f: Any = F { "v" }
            println(c.toString())
            println(f.toString())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics.map(\.code))")

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        #expect(!mainBody.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == "kk_object_register_any_to_string"
        }, "member extensions must not occupy the erased-Any toString slot")
    }
}
#endif
