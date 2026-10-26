@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IndexedMemberExtensionScopeTests {
    @Test
    func memberExtensionGetAndSetResolveForIndexedPostfixIncrementInWithScope() throws {
        let ctx = makeContextFromSource("""
        fun <T, R> with(receiver: T, block: T.() -> R): R = receiver.block()
        operator fun Long.inc() = 1L

        object ExtProvider {
            operator fun Long.get(i: Int) = this
            operator fun Long.set(i: Int, newValue: Long) {}
        }

        fun main() {
            with(ExtProvider) {
                var x = 0L
                val y = x[0]++
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let extensionCalls = sema.bindings.callBindings.values.compactMap { binding -> (String, SymbolID)? in
            guard let owner = sema.symbols.memberExtensionOwnerSymbol(for: binding.chosenCallee),
                  let symbol = sema.symbols.symbol(binding.chosenCallee)
            else {
                return nil
            }
            return (ctx.interner.resolve(symbol.name), owner)
        }
        #expect(extensionCalls.map(\.0).sorted() == ["get", "set"])
        #expect(extensionCalls.allSatisfy {
            sema.symbols.symbol($0.1)?.name == ctx.interner.intern("ExtProvider")
        })
    }
}
