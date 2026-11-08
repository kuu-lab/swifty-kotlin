// KUU-4188: a named argument holding a nested generic constructor call must
// not inherit the inapplicable member overloads' function-type expectation.
// Members take `(Throwable?) -> Unit`; the internal JobNode extension is the
// real target (kotlinx.coroutines JobSupport.awaitSuspend shape).
interface DisposableHandle { fun dispose() }

open class JobNode {
    open operator fun invoke(cause: Throwable?) {}
}

interface Job {
    fun invokeOnCompletion(handler: (Throwable?) -> Unit): DisposableHandle
    fun invokeOnCompletion(
        onCancelling: Boolean,
        invokeImmediately: Boolean,
        handler: (Throwable?) -> Unit,
    ): DisposableHandle
}

internal fun Job.invokeOnCompletion(
    invokeImmediately: Boolean = true,
    handler: JobNode,
): DisposableHandle = object : DisposableHandle {
    override fun dispose() { println("disposed") }
}

class AwaitContinuation<T>

private class ResumeAwaitOnCompletion<T>(
    val continuation: AwaitContinuation<T>,
) : JobNode()

class JobSupport : Job {
    override fun invokeOnCompletion(handler: (Throwable?) -> Unit): DisposableHandle =
        object : DisposableHandle { override fun dispose() { println("member1") } }

    override fun invokeOnCompletion(
        onCancelling: Boolean,
        invokeImmediately: Boolean,
        handler: (Throwable?) -> Unit,
    ): DisposableHandle =
        object : DisposableHandle { override fun dispose() { println("member2") } }

    fun <T> awaitSuspend(cont: AwaitContinuation<T>): DisposableHandle =
        invokeOnCompletion(handler = ResumeAwaitOnCompletion(cont))
}

fun main() {
    val support = JobSupport()
    val handle = support.awaitSuspend(AwaitContinuation<String>())
    handle.dispose()
    println("done")
}
