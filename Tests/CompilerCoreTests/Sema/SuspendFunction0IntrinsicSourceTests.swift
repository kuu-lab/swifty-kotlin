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
            // Both the receiver-less (SuspendFunction0.kt) and the receiver-bearing
            // (SuspendFunction1.kt) overloads are bundled source; they differ in arity.
            #expect(overloads.allSatisfy(symbols.isSourceBackedSymbol))
            func sourcePath(ofParameterCount count: Int) throws -> String? {
                let overload = try #require(overloads.first {
                    symbols.functionSignature(for: $0)?.parameterTypes.count == count
                })
                return symbols.sourceFileID(for: overload).flatMap { ctx.sourceManager.path(of: $0) }
            }
            #expect(try sourcePath(ofParameterCount: 1) == "__bundled_kotlin/coroutines/intrinsics/SuspendFunction0.kt")
            #expect(try sourcePath(ofParameterCount: 2) == "__bundled_kotlin/coroutines/intrinsics/SuspendFunction1.kt")
        }
    }
}
#endif
