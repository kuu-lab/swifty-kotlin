// KUU-3901: `suspendCoroutine` inside a nested suspend lambda (the inline
// `onEach` argument) used to leave the `kk_lambda_*` decl non-suspend, so
// CoroutineLoweringPass skipped it and the inlined
// `<suspendCoroutineUninterceptedOrReturn>` marker failed the KIR verifier.
import kotlin.coroutines.*

object EmptyContinuation : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: kotlin.Result<Unit>) { result.getOrThrow() }
}
fun builder(c: suspend () -> Unit) { c.startCoroutine(EmptyContinuation) }

suspend fun <T> List<T>.onEach(c: suspend (T) -> Unit) { for (e in this) c(e) }
var c: Continuation<Any>? = null

fun main() {
    var res = ""
    builder {
        listOf("O", "K").onEach { res += suspendCoroutine<String> { cont ->
            @Suppress("UNCHECKED_CAST")
            c = cont as Continuation<Any>
        } }
    }
    c?.resume("O")
    c?.resume("K")
    println(res)
}
