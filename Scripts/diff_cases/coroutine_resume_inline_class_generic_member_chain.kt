// KUU-3782: a value class resumed into a generic member suspend chain must be
// boxed when it is staged into an erased `T` launcher slot; otherwise the
// callee's state machine reads the raw flat payload and the value arrives
// unboxed at the interface boundary.
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
value class IC(val s: String)

var c: Continuation<Any>? = null

suspend fun <T> suspendMe(): T = suspendCoroutine {
    @Suppress("UNCHECKED_CAST")
    c = it as Continuation<Any>
}

interface IBar {
    suspend fun bar(): IC
}

class Test1 : IBar {
    suspend fun <T> foo(value: T): T = value

    suspend fun qux(ss: IC): IC = IC(ss.s)

    suspend fun <T> quz(t: T): T = t

    override suspend fun bar(): IC {
        return foo(qux(quz(suspendMe())))
    }

    suspend fun test(): String {
        val b: IBar = this
        return b.bar().s
    }
}

class Test2 : IBar {
    suspend fun <T> foo(value: T): T = value

    override suspend fun bar(): IC {
        return foo(suspendMe())
    }

    suspend fun test(): String {
        val b: IBar = this
        return b.bar().s
    }
}

fun main() {
    var result = "FAIL"
    builder {
        result = Test1().test()
    }
    c?.resume(IC("OK"))
    if (result != "OK") {
        println("FAIL 1 $result")
        return
    }

    result = "FAIL2"
    builder {
        result = Test2().test()
    }
    c?.resume(IC("OK"))
    println(result)
}
