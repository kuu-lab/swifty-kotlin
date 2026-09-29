#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SuspendFunction0IntrinsicSourceTests {
    @Test
    func noReceiverIntrinsicsHaveSourceBodies() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
        import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

        fun <T> prepare(function: suspend () -> T, completion: Continuation<T>) =
            function.createCoroutineUnintercepted(completion)

        fun <T> start(function: suspend () -> T, completion: Continuation<T>): Any? =
            function.startCoroutineUninterceptedOrReturn(completion)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let symbols = try #require(ctx.sema?.symbols)
        let prefix = ["kotlin", "coroutines", "intrinsics"].map(ctx.interner.intern)
        for name in ["createCoroutineUnintercepted", "startCoroutineUninterceptedOrReturn"] {
            let overloads = symbols.lookupAll(fqName: prefix + [ctx.interner.intern(name)])
            #expect(overloads.count == 2)
            let backed = overloads.filter(symbols.isSourceBackedSymbol)
            #expect(backed.count == 1)
            let fileID = try #require(backed.first.flatMap { symbols.sourceFileID(for: $0) })
            #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/coroutines/intrinsics/SuspendFunction0.kt")
        }
    }
}
#endif
