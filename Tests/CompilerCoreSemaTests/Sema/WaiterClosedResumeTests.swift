#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct WaiterClosedResumeTests {
    // The upstream continuation member requires two arguments. The bundled
    // version supplies a default, so using that API would miss the extension
    // receiver's contribution to the nested generic factory's expected type.
    @Test(arguments: [false, true])
    func starProjectedWaiterResumesNestedClosedResult(bundledAPI: Bool) throws {
        let implementationVariance = bundledAPI ? "" : "in "
        let cancellationDefault = bundledAPI ? " = null" : ""
        let ctx = try semaContext(from: """
        package waiter
        import waiter.ChannelResult.Companion.closed

        interface Waiter
        interface Continuation<in T> {
            fun resumeWith(value: T)
        }
        fun <T> Continuation<T>.resume(value: T) = resumeWith(value)
        interface CancellableContinuation<in T> : Continuation<T> {
            fun resume(value: T, onCancellation: ((Throwable) -> Unit)?\(cancellationDefault))
        }
        abstract class CancellableContinuationImpl<\(implementationVariance)T> : CancellableContinuation<T>, Waiter
        class ChannelResult<out T> {
            companion object {
                fun <E> closed(cause: Throwable?): ChannelResult<E> = ChannelResult()
            }
        }
        class ReceiveCatching<E>(val cont: CancellableContinuationImpl<ChannelResult<E>>) : Waiter by cont
        class BufferedChannel<E>(val closeCause: Throwable?) {
            fun Waiter.resumeWaiterOnClosedChannel() {
                when (this) {
                    is ReceiveCatching<*> -> cont.resume(closed(closeCause))
                }
            }
        }
        """, includeStdlib: false)
        let sema = try #require(ctx.sema)
        let calleePath = bundledAPI
            ? ["waiter", "CancellableContinuation", "resume"]
            : ["waiter", "resume"]
        let resume = try #require(sema.symbols.lookup(
            fqName: calleePath.map(ctx.interner.intern)
        ))
        let binding = try #require(sema.bindings.callBindings.values.first {
            $0.chosenCallee == resume
        })
        #expect(binding.substitutedTypeArguments.count == 1)
        let resultType = try #require(binding.substitutedTypeArguments.first)
        guard case let .classType(resultClass) = sema.types.kind(of: resultType) else {
            Issue.record("Expected ChannelResult as resume's inferred type argument")
            return
        }
        #expect(sema.symbols.symbol(resultClass.classSymbol)?.fqName ==
            ["waiter", "ChannelResult"].map(ctx.interner.intern))
    }
}
#endif
