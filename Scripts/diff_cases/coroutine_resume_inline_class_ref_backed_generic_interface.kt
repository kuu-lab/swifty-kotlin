// KUU-3782: a reference-backed value class (`IC(val s: Any)`) resumed through
// an erased generic interface bridge must be unboxed with
// `kk_value_class_unbox`; the boxing table has no primitive unbox callee for
// `Any`, so the bridge previously re-boxed the completion (nesting the value)
// and treated `COROUTINE_SUSPENDED` as a resumed value.
import kotlin.coroutines.*

object EmptyContinuation : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) {
        result.getOrThrow()
    }
}

fun builder(c: suspend () -> Unit) {
    c.startCoroutine(EmptyContinuation)
}

@JvmInline
value class IC(val s: Any)

var c: Continuation<Any>? = null

suspend fun <T> suspendMe(): T = suspendCoroutine {
    @Suppress("UNCHECKED_CAST")
    c = it as Continuation<Any>
}

interface Base<T> {
    suspend fun generic(): T
}

class Derived : Base<IC> {
    override suspend fun generic(): IC = suspendMe()
}

fun main() {
    var res: String? = null
    builder {
        val base: Base<*> = Derived()
        res = (base.generic() as IC).s as String
    }
    c?.resume(IC("OK"))
    println(res)
}
