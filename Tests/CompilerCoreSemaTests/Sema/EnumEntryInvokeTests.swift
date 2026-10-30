@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct EnumEntryInvokeTests {
    @Test
    func enumEntryCallResolvesThroughEnumMemberInvoke() throws {
        let ctx = makeContextFromSource("""
        enum class Invocable {
            ONE, TWO;
            operator fun invoke(value: Int): Int = value
            fun echo(value: Int): Int = value
        }

        enum class GenericInvocable {
            ONE;
            operator fun <T> invoke(value: T): T = value
        }

        class Callable {
            operator fun invoke(value: Int): Int = value
        }

        fun sample(): Int = Invocable.ONE(42)
            + Invocable.TWO.echo(42)
            + GenericInvocable.ONE("OK").length
            + Callable()(42)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let entryCall = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(receiver, name, _, args, _) = ast.arena.expr(id),
                  ctx.interner.resolve(name) == "ONE",
                  !args.isEmpty,
                  case .nameRef = ast.arena.expr(receiver)
            else {
                return nil
            }
            return id
        }.first)
        let binding = try #require(sema.bindings.callBinding(for: entryCall))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.name == ctx.interner.intern("invoke"))
        let entrySymbol = try #require(sema.bindings.enumEntryInvokeReceiverSymbol(for: entryCall))
        #expect(sema.symbols.symbol(entrySymbol)?.name == ctx.interner.intern("ONE"))
    }

    @Test
    func nonInvocableEnumEntryCallRemainsRejected() throws {
        let ctx = makeContextFromSource("""
        enum class NotInvocable { ONE }
        fun invalid() = NotInvocable.ONE(42)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test
    func privateEnumMemberInvokeRemainsInaccessible() throws {
        let ctx = makeContextFromSource("""
        enum class Hidden {
            ONE;
            private operator fun invoke(value: Int): Int = value
        }
        fun invalid() = Hidden.ONE(42)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.message.contains("private") })
    }
}
