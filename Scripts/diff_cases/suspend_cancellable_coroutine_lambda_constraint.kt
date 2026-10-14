import kotlin.coroutines.*
import kotlinx.coroutines.*

// KUU-2053: keep the original ktor-io inference site, including the nested call.
private inline fun <reified T : Any> trySuspend(task: T, crossinline s: () -> Boolean) {}

private suspend inline fun <reified T : Any> sleepWhile(
    crossinline createTask: (Continuation<Unit>) -> T,
    crossinline shouldSleep: () -> Boolean
) {
    while (shouldSleep()) {
        suspendCancellableCoroutine { cont ->
            trySuspend<T>(createTask(cont), shouldSleep)
        }
    }
}

private suspend fun inferredUnit(resume: (Continuation<Unit>) -> Unit) {
    suspendCancellableCoroutine { cont -> resume(cont) }
}

private suspend fun inferredUnitInvoke(resume: (Continuation<Unit>) -> Unit) {
    suspendCancellableCoroutine { cont -> resume.invoke(cont) }
}

fun main() = runBlocking {
    sleepWhile({ "unused" }, { false })
    inferredUnit { it.resumeWith(Result.success(Unit)) }
    println("inferred Unit")
    inferredUnitInvoke { it.resumeWith(Result.success(Unit)) }
    println("inferred invoke Unit")
}
