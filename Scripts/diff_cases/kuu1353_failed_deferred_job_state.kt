// KUU-1353: a failed async/Deferred must reach terminal job state —
// isCompleted=true, isCancelled=true, getCompleted() rethrows the failure
// exception, getCompletionExceptionOrNull() returns it. The state machine
// used to leave the deferred "not completed" after await() surfaced the
// exception, so every Job state accessor lied and getCompleted() /
// getCompletionExceptionOrNull() threw "This job has not completed yet".
@file:OptIn(ExperimentalCoroutinesApi::class)

import kotlinx.coroutines.*

fun main() {
    try {
        runBlocking {
            // Successful deferred: terminal-completed, not cancelled.
            val ok = async { 7 }
            println("ok.await=" + ok.await())
            println("ok.isCompleted=" + ok.isCompleted)
            println("ok.isActive=" + ok.isActive)
            println("ok.isCancelled=" + ok.isCancelled)
            println("ok.getCompleted=" + ok.getCompleted())
            println("ok.ex=" + ok.getCompletionExceptionOrNull())

            // Explicitly cancelled deferred: terminal-cancelled; join() is a
            // no-op because the *caller* is still healthy. CancellationException
            // messages differ from kotlinx ("DeferredCoroutine was cancelled"),
            // so only the exception type is asserted.
            val c = async { 1 }
            c.cancel()
            try { c.await() } catch (e: Throwable) { println("c.await threw isCE=" + (e is CancellationException)) }
            println("c.isCompleted=" + c.isCompleted)
            println("c.isActive=" + c.isActive)
            println("c.isCancelled=" + c.isCancelled)
            try { c.getCompleted(); println("c.gc-ok") } catch (e: Throwable) { println("c.gc threw isCE=" + (e is CancellationException)) }
            println("c.ex isCE=" + (c.getCompletionExceptionOrNull() is CancellationException))
            try { c.join(); println("c.join-ok") } catch (e: Throwable) { println("c.join threw") }

            // Failed deferred: await surfaces the failure, and afterwards the
            // job must still report terminal state. join() throws because the
            // failure propagated upward and cancelled the caller — the kotlinx
            // message ("BlockingCoroutine is cancelling") differs, so assert
            // the type only. The scope rethrows the child failure at the end.
            val f = async { throw IllegalStateException("x") }
            try { f.await() } catch (e: Throwable) { println("f.await threw ise=" + (e is IllegalStateException) + " msg=" + e.message) }
            println("f.isCompleted=" + f.isCompleted)
            println("f.isActive=" + f.isActive)
            println("f.isCancelled=" + f.isCancelled)
            try { f.getCompleted(); println("f.gc-ok") } catch (e: Throwable) { println("f.gc threw ise=" + (e is IllegalStateException) + " msg=" + e.message) }
            val fex = f.getCompletionExceptionOrNull()
            println("f.ex ise=" + (fex is IllegalStateException) + " msg=" + fex?.message)
            try { f.join(); println("f.join-ok") } catch (e: Throwable) { println("f.join threw isCE=" + (e is CancellationException)) }
            println("done")
        }
    } catch (e: IllegalStateException) { println("scope rethrew " + e.message) }
}
