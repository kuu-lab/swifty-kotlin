#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ReceiveCatchingInlineTypeInferenceTests {
    @Test
    func genericExtensionCallbackKeepsItsReceiverInputType() throws {
        try withTemporaryFile(contents: """
        class LetInput {
            fun value(): Int = 1
        }

        private inline fun <T, R> T.letLike(block: (T) -> R): R = block(this)

        fun readValue(input: LetInput): Int = input.letLike { it.value() }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected the extension receiver to specialize the callback input, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test
    func inlineReceiveImplUsesExpectedReturnForResultOnlyFactory() throws {
        try withTemporaryFile(contents: """
        // Mirrors the relevant bundled ChannelResult generic shape while keeping
        // this regression focused on inference rather than stdlib loading. The
        // `closed` parameter type is opaque because only its result-only `T` matters.
        class ChannelResult<out T> {
            companion object {
                fun <T> success(value: T): ChannelResult<T> = ChannelResult()
                fun <T> closed(cause: Any?): ChannelResult<T> = ChannelResult()
            }
        }

        class BufferedChannel<E> {
            private inline fun <R> receiveImpl(
                onElementRetrieved: (E) -> R,
                onSuspend: (Any?, Int, Long) -> R,
                onClosed: () -> R,
                onNoWaiterSuspend: (Any?, Int, Long) -> R
            ): R = onClosed()

            suspend fun receiveCatching(): ChannelResult<E> = receiveImpl(
                onElementRetrieved = { element -> ChannelResult.success(element) },
                onSuspend = { _, _, _ -> null!! },
                onClosed = { ChannelResult.closed(null) },
                onNoWaiterSuspend = { _, _, _ -> null!! }
            )
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected receiveImpl's callback result to infer as ChannelResult<E>, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
#endif
