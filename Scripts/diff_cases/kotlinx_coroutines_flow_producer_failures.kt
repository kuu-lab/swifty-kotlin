import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.channels.*

fun failedChannel(): Flow<Int> = channelFlow<Int> { send(1); delay(1); throw RuntimeException("channel") }
fun failedCallback(): Flow<Int> = callbackFlow<Int> { send(2); delay(1); throw RuntimeException("callback") }
fun failedChild(): Flow<Int> = channelFlow<Int> {
    launch { send(7); delay(1); throw RuntimeException("child") }
}
fun retriedProducer(): Flow<Int> {
    var attempt = 0
    return channelFlow<Int> {
        attempt++
        send(attempt)
        delay(1)
        if (attempt < 2) throw RuntimeException("retry")
    }
}

fun main() = runBlocking {
    try {
        failedChannel()
            .collect { println("channel-value: $it") }
        println("channel-no-throw")
    } catch (e: Throwable) { println("channel-caught: ${e.message}") }
    println("channel-done")
    try {
        failedCallback()
            .collect { println("callback-value: $it") }
        println("callback-no-throw")
    } catch (e: Throwable) { println("callback-caught: ${e.message}") }
    println("callback-done")
    channelFlow<Int> { send(3); delay(1); throw RuntimeException("caught") }
        .catch { println("catch: ${it.message}"); emit(4) }
        .collect { println("catch-value: $it") }
    println("catch-done")
    try {
        channelFlow<Int> { send(5); delay(1); throw RuntimeException("mapped") }
            .map { it * 2 }
            .onCompletion { cause -> println("completion: ${cause?.message}") }
            .collect { println("map-value: $it") }
    } catch (e: Throwable) { println("map-caught: ${e.message}") }
    println("map-done")
    retriedProducer().retry(1) { println("retry: ${it.message}"); true }
        .collect { println("retry-value: $it") }
    println("retry-done")
    channelFlow<Int> { send(6) }.collect { println("success-value: $it") }
    println("success-done")
    try {
        failedChild().collect { println("child-value: $it") }
        println("child-no-throw")
    } catch (e: Throwable) { println("child-caught: ${e.message}") }
    println("child-done")
    try {
        channelFlow<Int> { close(); throw RuntimeException("after-close") }.collect { println(it) }
        println("close-no-throw")
    } catch (e: Throwable) { println("close-caught: ${e.message}") }
    println("close-done")
    channelFlow<Int> { close(); awaitCancellation() }.collect { println(it) }
    println("manual-close-done")
    try {
        channelFlow<Int> {
            try { send(1); awaitCancellation() }
            finally { throw RuntimeException("cleanup") }
        }.take(1).collect { println("take-value: $it") }
        println("take-no-throw")
    } catch (e: Throwable) { println("take-caught: ${e.message}") }
    println("take-done")
    channelFlow<Int> { var n = 0; while (true) { send(n++) } }
        .take(1).catch { println("infinite-caught: ${it.message}") }
        .collect { println("infinite-value: $it") }
    println("infinite-done")
    channelFlow<Int> { send(8) }
        .onCompletion { println("before-take-cancelled: ${it != null}") }
        .take(1).collect { println("before-take-value: $it") }
    channelFlow<Int> { send(9) }.take(1)
        .onCompletion { println("after-take-success: ${it == null}") }
        .collect { println("after-take-value: $it") }
    flow<Int> {
        channelFlow<Int> { send(10) }.transform { emit(it) }.collect { emit(it) }
    }.collect { println("nested-value: $it") }
    try {
        channelFlow<Int> { throw RuntimeException("predicate") }
            .retryWhen { _, _ -> emit(42); false }
            .collect { println("predicate-value: $it") }
    } catch (e: Throwable) { println("predicate-caught: ${e.message}") }
    channelFlow<Int> { send(11) }.transform<Int, Int> {
        emit(it)
        throw RuntimeException("after-emit")
    }.take(1).collect { println("transform-value: $it") }
    println("transform-done")
    channelFlow<Int> { throw RuntimeException("caught-emitter") }.catch {
        emit(12)
        throw RuntimeException("after-catch")
    }.take(1).collect { println("catch-take-value: $it") }
    println("catch-take-done")
    channelFlow<Int> { send(13); close(IllegalStateException("closed")) }
        .take(1).collect { println("closed-take-value: $it") }
    println("closed-take-done")
    try {
        callbackFlow<Int> {
            close(IllegalStateException("close-first"))
            try { awaitCancellation() }
            finally { throw IllegalArgumentException("cleanup-second") }
        }.collect { println(it) }
    } catch (e: Throwable) { println("close-priority: ${e.message}") }
    val never = Channel<Int>()
    val child = launch { never.receive() }
    delay(10)
    child.cancel()
    child.join()
    println("cancelled-child-done")
    channelFlow<Int> { throw CancellationException("explicit") }
        .catch { println("explicit-caught: ${it.message}"); emit(99) }
        .collect { println("explicit-value: $it") }
    var cancellationAttempt = 0
    channelFlow<Int> {
        cancellationAttempt++
        if (cancellationAttempt == 1) throw CancellationException("retry-explicit")
        send(100)
    }.retry(1) { println("explicit-retry: ${it.message}"); true }
        .collect { println("explicit-retry-value: $it") }
    val bufferedReady = Channel<Int>(1)
    var bufferedFailure = "missing"
    try {
        channelFlow<Int> {
            send(20); send(21); send(22)
            bufferedReady.send(1)
            throw RuntimeException("buffered")
        }.catch { bufferedFailure = it.message ?: "null" }
            .collect {
                if (it == 20) { bufferedReady.receive(); delay(60000) }
                println("buffered-unexpected-value: $it")
            }
    } catch (e: Throwable) { bufferedFailure = e.message ?: "null" }
    println("buffered-failure: $bufferedFailure")
    try {
        channelFlow<Int> { send(24); awaitCancellation() }
            .catch { println("downstream-catch-unexpected") }
            .retry(1) { println("downstream-retry-unexpected"); true }
            .collect { throw RuntimeException("downstream") }
    } catch (e: Throwable) { println("downstream-caught: ${e.message}") }
    val childReady = Channel<Int>(1)
    val childCleaned = Channel<Int>(1)
    channelFlow<Int> {
        launch {
            try { childReady.send(1); awaitCancellation() }
            finally { childCleaned.trySend(1) }
        }
        childReady.receive()
        send(25)
        awaitCancellation()
    }.take(1).collect { println("child-take-value: $it") }
    println("child-take-cleaned: ${childCleaned.receive()}")
    val collectorEntered = Channel<Int>()
    try {
        channelFlow<Int> {
            send(26)
            collectorEntered.receive()
            throw RuntimeException("long-delay")
        }.catch { println("long-delay-catch-unexpected") }
            .collect { collectorEntered.send(1); delay(60000) }
    } catch (e: Throwable) { println("long-delay-caught: ${e.message}") }
    val parentReady = Channel<Int>()
    val cancelledCollect = launch {
        channelFlow<Int> { parentReady.send(1); awaitCancellation() }
            .catch { println("parent-catch-unexpected") }
            .retry(1) { println("parent-retry-unexpected"); true }
            .collect { println(it) }
    }
    parentReady.receive()
    delay(1)
    cancelledCollect.cancel()
    cancelledCollect.join()
    println("parent-cancel-done")
    val cleanupStarted = Channel<Int>()
    val collectorCleaned = Channel<Int>(1)
    try {
        channelFlow<Int> {
            launch {
                try { cleanupStarted.send(1); awaitCancellation() }
                finally { withContext(NonCancellable) { collectorCleaned.receive() } }
            }
            cleanupStarted.receive()
            send(28)
            collectorEntered.receive()
            throw RuntimeException("cleanup-handshake")
        }.collect {
            collectorEntered.send(1)
            try { awaitCancellation() }
            finally { collectorCleaned.trySend(1) }
        }
    } catch (e: Throwable) { println("cleanup-handshake-caught: ${e.message}") }
    var scopedChildDone = false
    channelFlow<Int> { send(29) }.collect {
        CoroutineScope(currentCoroutineContext()).launch {
            delay(1)
            scopedChildDone = true
        }
    }
    println("scoped-child-done: $scopedChildDone")
    try {
        channelFlow<Int> { send(30) }.collect {
            CoroutineScope(currentCoroutineContext()).launch {
                delay(1)
                throw RuntimeException("scoped-child")
            }
        }
    } catch (e: Throwable) { println("scoped-child-caught: ${e.message}") }
    val scopedReady = Channel<Int>()
    val waitForScopedChild = launch {
        channelFlow<Int> { send(31) }.collect {
            CoroutineScope(currentCoroutineContext()).launch {
                scopedReady.send(1)
                awaitCancellation()
            }
        }
        println("scoped-parent-after-unexpected")
    }
    scopedReady.receive()
    waitForScopedChild.cancel()
    waitForScopedChild.join()
    println("scoped-parent-cancel-done")
    val scopedDelayReady = Channel<Int>()
    var scopedDelayCleaned = false
    val waitForScopedDelay = launch {
        channelFlow<Int> { send(33) }.collect {
            CoroutineScope(currentCoroutineContext()).launch {
                try {
                    scopedDelayReady.send(1)
                    delay(60_000)
                } finally { scopedDelayCleaned = true }
            }
        }
        println("scoped-delay-after-unexpected")
    }
    scopedDelayReady.receive()
    waitForScopedDelay.cancel()
    waitForScopedDelay.join()
    println("scoped-delay-cancel-done: $scopedDelayCleaned")
    try {
        channelFlow<Int> { send(32) }.collect {
            CoroutineScope(currentCoroutineContext()).async(Dispatchers.Default) {
                throw RuntimeException("scoped-async")
            }
        }
    } catch (e: Throwable) { println("scoped-async-caught: ${e.message}") }
    println("done")
}
