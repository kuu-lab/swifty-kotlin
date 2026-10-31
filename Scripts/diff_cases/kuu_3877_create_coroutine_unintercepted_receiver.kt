// KUU-3877: createCoroutineUnintercepted(receiver, completion) must deliver
// the explicit receiver/argument to a suspend function value. The resolved
// path seeds the callable box's closure environment in launcher slot 0 and
// the receiver in slot 1, matching the runtime's
// createCoroutineFromFunctionValue ABI.
import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted

private class RecordingContinuation(
    override val context: CoroutineContext = EmptyCoroutineContext,
) : Continuation<Any?> {
    var resumed: Any? = null

    override fun resumeWith(result: Result<Any?>) {
        result.onSuccess { resumed = it }
    }
}

fun main() {
    // Parameter-position value on a suspend function value.
    val f: suspend (Int) -> Int = { it * 3 }
    val completion = RecordingContinuation()
    f.createCoroutineUnintercepted(5, completion).resumeWith(Result.success(Unit))
    println(completion.resumed)

    // Extension-receiver value on a suspend function value.
    val g: suspend Int.() -> Int = { this * 4 }
    val completion2 = RecordingContinuation()
    g.createCoroutineUnintercepted(6, completion2).resumeWith(Result.success(Unit))
    println(completion2.resumed)
}
