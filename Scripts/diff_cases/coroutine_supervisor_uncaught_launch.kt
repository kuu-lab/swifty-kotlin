import kotlinx.coroutines.*

// KUU-1422: an uncaught `launch` failure inside supervisorScope must reach the
// JVM-style uncaught report on stderr while supervisor semantics hold — the
// sibling finishes and the caller continues (JVM exits 0). The harness
// compares stdout + exit code; the stderr report text itself is pinned by
// BundledStdlibExecutionTests+CoroutineUncaughtLaunch.
//
// The second half pins the explicit CoroutineExceptionHandler contract: a
// handler in the launch context consumes the failure and no report fires.

fun main() = runBlocking {
    supervisorScope {
        launch { delay(10); println("sup-sib-alive") }
        launch { delay(1); throw IllegalStateException("y") }
    }
    println("after")

    val handler = CoroutineExceptionHandler { _, _ -> println("handled") }
    supervisorScope {
        launch { delay(10); println("sup-sib2-alive") }
        launch(handler) { delay(1); throw IllegalStateException("z") }
    }
    println("done")
}
