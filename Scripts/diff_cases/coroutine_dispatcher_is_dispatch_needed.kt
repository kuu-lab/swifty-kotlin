// KUU-3910: the kotlinx-coroutines internal APIs real libraries rely on must
// resolve in the bundled coroutines — `CoroutineDispatcher.isDispatchNeeded`
// (ktor-utils SuspendFunctionGun.kt) and `kotlinx.coroutines.internal`
// recoverStackTrace/unwrap/recoverAndThrow (ktor-utils StackTraceRecover.kt).
import kotlinx.coroutines.*
import kotlin.coroutines.*

fun main() {
    // Upstream open member: true for the standard dispatchers, false for
    // Dispatchers.Unconfined.
    println("default:${Dispatchers.Default.isDispatchNeeded(EmptyCoroutineContext)}")
    println("io:${Dispatchers.IO.isDispatchNeeded(EmptyCoroutineContext)}")
    println("unconfined:${Dispatchers.Unconfined.isDispatchNeeded(EmptyCoroutineContext)}")

    // Upstream internal API — called under the same suppression Ktor uses.
    // Without the debug agent stack recovery is a no-op, so identity holds.
    val boom = IllegalStateException("boom")
    val cont = object : Continuation<Unit> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) {}
    }
    @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
    val twoArg = kotlinx.coroutines.internal.recoverStackTrace(boom, cont)
    println("twoArg:${twoArg === boom}:${twoArg.message}")
    @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
    val oneArg = kotlinx.coroutines.internal.recoverStackTrace(boom)
    println("oneArg:${oneArg === boom}:${oneArg.message}")
    @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
    val unwrapped = kotlinx.coroutines.internal.unwrap(boom)
    println("unwrap:${unwrapped === boom}")

    runBlocking {
        try {
            @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
            kotlinx.coroutines.internal.recoverAndThrow(boom)
            println("throw:unreached")
        } catch (e: IllegalStateException) {
            println("throw:${e === boom}:${e.message}")
        }
    }
}
