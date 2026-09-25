package kotlinx.coroutines

// KUU-CORO-101: a plain functional interface, so `DisposableHandle { ... }`
// (the common construction idiom, e.g. as the result of
// `Job.invokeOnCompletion`) resolves through the general SAM-conversion
// mechanism -- no runtime bridging needed here.
public fun interface DisposableHandle {
    public fun dispose()
}
