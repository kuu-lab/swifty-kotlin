// KUU-3299: an erased generic interface bridge must unbox a suspend result
// before boxing it for the interface slot, or the value-class payload nests.
import kotlin.coroutines.*

@JvmInline
value class IC(val s: String)

interface Base<T> {
    suspend fun g(): T
}

class D : Base<IC> {
    override suspend fun g(): IC = suspendCoroutine {
        it.resume(IC("OK"))
    }
}

fun main() {
    val base: Base<*> = D()
    val work: suspend () -> Unit = {
        println((base.g() as IC).s)
    }
    work.startCoroutine(object : Continuation<Unit> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) {
            result.getOrThrow()
        }
    })
}
