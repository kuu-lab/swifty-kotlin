import kotlin.coroutines.*

// KUU-3900: a `suspend` interface method implemented through `by` delegation
// delivered null instead of the delegate's result. The synthesized forwarding
// body's shared result temp carried a `.null` literal expression kind, so
// codegen's flat-string argument marshalling (isZeroConstant ->
// buildNullStringAggregate) substituted a null aggregate at the coroutine
// merge point and kk_coroutine_state_exit observed null. Covers both a
// delegate that actually suspends/resumes and one that completes
// synchronously.

object EmptyContinuation : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: kotlin.Result<Unit>) { result.getOrThrow() }
}
fun builder(c: suspend () -> Unit) { c.startCoroutine(EmptyContinuation) }

var saved: Continuation<Any>? = null

suspend fun <T> suspendMe(): T = suspendCoroutine {
    @Suppress("UNCHECKED_CAST")
    saved = it as Continuation<Any>
}

interface I { suspend fun foo(s: String): String }
class D : I {
    override suspend fun foo(s: String): String = suspendMe()
}
class C(val d: I) : I by d

interface J { suspend fun bar(): String }
class E : J {
    override suspend fun bar(): String = "SYNC"
}
class F(val e: J) : J by e

fun main() {
    val d = D()
    builder {
        val x: Any? = C(d).foo("IGNORE ME")
        println("foo delivered: ${x == null} $x")
    }
    saved?.resume("OK")
    builder {
        val y: Any? = F(E()).bar()
        println("bar delivered: ${y == null} $y")
    }
}
