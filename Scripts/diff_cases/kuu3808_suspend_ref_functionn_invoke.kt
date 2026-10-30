// KUU-3808 / KT-66098: a suspend function value invoked through its erased
// non-suspend `FunctionN` view carries the completion continuation in the
// last argument slot. The body runs synchronously to its first real
// suspension; invoke then returns the bare result or COROUTINE_SUSPENDED.
import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

class RecordingContinuation(override val context: CoroutineContext = EmptyCoroutineContext) : Continuation<Any?> {
    var resumed: Any? = null
    override fun resumeWith(result: Result<Any?>) { result.onSuccess { resumed = it } }
}

open class EmptyContinuation(override val context: CoroutineContext = EmptyCoroutineContext) : Continuation<Any?> {
    override fun resumeWith(result: Result<Any?>) { result.getOrThrow() }
}

suspend fun neverResumes(v: Int): Int {
    return suspendCoroutineUninterceptedOrReturn<Int> { cont ->
        COROUTINE_SUSPENDED
    }
}

class Foo(val x: Int) {
    suspend fun bar(y: Int) = y + x
    suspend fun hanging(y: Int): Int = neverResumes(y + x)
}

suspend fun topLevel(y: Int) = y * 2

fun main() {
    // Bound member ref, synchronously completing body -> bare result.
    val ref = Foo(42)::bar
    println((ref as Function2<Int, Continuation<Int>, Any?>)(117, EmptyContinuation()))

    // Unbound member ref: receiver becomes the first parameter.
    val uref = Foo::bar
    println((uref as Function3<Foo, Int, Continuation<Int>, Any?>)(Foo(5), 20, EmptyContinuation()))

    // Top-level suspend function ref.
    val tref = ::topLevel
    println((tref as Function2<Int, Continuation<Int>, Any?>)(21, EmptyContinuation()))

    // Suspend lambda.
    val lambda: suspend (Int) -> Int = { it + 7 }
    println((lambda as Function2<Int, Continuation<Int>, Any?>)(3, EmptyContinuation()))

    // Body that really suspends -> invoke returns COROUTINE_SUSPENDED.
    val href = Foo(1)::hanging
    val cont = RecordingContinuation()
    val r = (href as Function2<Int, Continuation<Int>, Any?>)(10, cont)
    println(r === COROUTINE_SUSPENDED)
    println(cont.resumed)
}
