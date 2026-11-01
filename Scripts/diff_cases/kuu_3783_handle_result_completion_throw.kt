import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.startCoroutine
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

// KUU-3783: a `handleResultContinuation`-style completion whose `getOrThrow()`
// throws inside `resumeWith` must deliver that exception back to the call
// site that resumed the coroutine — the single-call-stack behavior JVM
// `resume` exhibits. The exception used to be dropped on the continuation
// relay between the child suspend machine and the completion continuation,
// so coroutines suspended inside try/catch/finally crashed with
// KSWIFTK-LINK-0003 or silently swallowed the failure.

private fun <T> handleResultContinuation(x: (T) -> Unit): Continuation<T> =
    object : Continuation<T> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<T>) {
            x(result.getOrThrow())
        }
    }

private var globalResult = ""
private var wasCalled = false

private class Controller {
    val postponedActions = ArrayList<() -> Unit>()

    suspend fun suspendWithValue(v: String): String = suspendCoroutineUninterceptedOrReturn { x ->
        postponedActions.add { x.resume(v) }
        COROUTINE_SUSPENDED
    }

    suspend fun suspendWithException(e: Exception): String = suspendCoroutineUninterceptedOrReturn { x ->
        postponedActions.add { x.resumeWithException(e) }
        COROUTINE_SUSPENDED
    }

    fun run(c: suspend Controller.() -> String) {
        c.startCoroutine(this, handleResultContinuation { globalResult = it })
        while (postponedActions.isNotEmpty()) {
            val action = postponedActions.removeAt(0)
            action()
        }
    }
}

private fun builder(expectException: Boolean = false, c: suspend Controller.() -> String) {
    val controller = Controller()
    globalResult = "#"
    wasCalled = false
    if (!expectException) {
        controller.run(c)
    } else {
        try {
            controller.run(c)
            globalResult = "fail: exception was not thrown"
        } catch (e: Exception) {
            globalResult = e.message!!
        }
    }
    if (!wasCalled) throw RuntimeException("fail wasCalled")
    if (globalResult != "OK") throw RuntimeException("fail $globalResult")
}

private fun commonThrow(t: Throwable) {
    throw t
}

fun main() {
    // Success path: suspension inside try/catch.
    builder {
        try {
            suspendWithValue("<ignored>")
            wasCalled = true
            suspendWithValue("OK")
        } catch (e: RuntimeException) {
            suspendWithValue("fail 1")
        }
    }
    // resumeWithException caught by a suspended catch block.
    builder {
        try {
            suspendWithException(RuntimeException("M"))
        } catch (e: RuntimeException) {
            if (e.message != "M") throw RuntimeException("fail 2")
            wasCalled = true
            suspendWithValue("OK")
        }
    }
    // Failure delivered to the completion continuation: `getOrThrow` inside
    // handleResultContinuation.resumeWith throws back through the resume
    // call site into `builder`'s catch.
    builder(expectException = true) {
        try {
            wasCalled = true
            suspendWithException(Exception("OK"))
        } catch (e: RuntimeException) {
            suspendWithValue("fail")
            throw RuntimeException("fail 3")
        }
    }
    // Suspension inside finally during exceptional unwinding.
    builder(expectException = true) {
        try {
            suspendWithValue("OK")
            commonThrow(Exception("OK"))
            suspendWithValue("456")
        } finally {
            if (suspendWithValue("G") != "G") throw RuntimeException("fail 4")
            wasCalled = true
        }
    }
    // Plain finally with suspension on the success path.
    builder {
        try {
            suspendWithValue("OK")
        } finally {
            if (suspendWithValue("G") != "G") throw RuntimeException("fail 5")
            wasCalled = true
        }
    }
    println(globalResult)
}
