// DIFF_CANDIDATE_ONLY: kotlin.native.concurrent.Worker has no JVM kotlinc oracle.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu2685_mutable_state_flow_concurrency.expected.stdout
@file:Suppress("DEPRECATION_ERROR")
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.TransferMode
import kotlin.native.concurrent.Worker
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.getAndUpdate
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.updateAndGet

private suspend fun awaitCondition(label: String, condition: () -> Boolean) {
    var remaining = 100_000
    while (remaining > 0 && !condition()) {
        delay(1)
        remaining -= 1
    }
    check(condition()) { "Timed out waiting for $label" }
}

data class Box(val number: Int)

// Worker.execute jobs must be non-capturing, so the shared flow and the
// per-worker parameters travel through the produced input value. The job
// bodies live in top-level functions: inside the runBlocking scope a property
// access on the job parameter would count as a captured (non-function) symbol
// and trip KSWIFTK-SEMA-0430.
private class Work(
    val flow: MutableStateFlow<Int>,
    val mode: Int,
    val increments: Int
)

private fun runIncrements(work: Work): Int {
    val flow = work.flow
    var done = 0
    while (done < work.increments) {
        when (work.mode % 4) {
            0 -> flow.update { it + 1 }
            1 -> {
                var swapped = false
                while (!swapped) {
                    val current = flow.value
                    swapped = flow.compareAndSet(current, current + 1)
                }
            }
            2 -> flow.updateAndGet { it + 1 }
            else -> flow.getAndUpdate { it + 1 }
        }
        done += 1
    }
    return done
}

private fun emitRange(flow: MutableStateFlow<Int>): Int {
    var i = 0
    while (i < 200) {
        i += 1
        flow.value = i
    }
    return i
}

// KUU-2685: MutableStateFlow.compareAndSet/update must be atomic and collector
// registration/notification must survive concurrent emit + cancellation.
fun main() = runBlocking {
    // CAS keeps the equality contract and stores nothing when the update is
    // already equal, so equal values keep their identity.
    val state = MutableStateFlow(10)
    println(state.compareAndSet(9, 11))
    println(state.compareAndSet(10, 20))
    println(state.value)
    println(state.compareAndSet(20, 20))
    println(state.value)

    val boxes = MutableStateFlow(Box(1))
    val original = boxes.value
    println(boxes.compareAndSet(Box(1), Box(1)))
    println(boxes.value === original)
    println(boxes.compareAndSet(Box(1), Box(2)))
    println(boxes.value)

    // A live collector must not observe the equal re-assignment.
    val conflated = MutableStateFlow(0)
    val seen = mutableListOf<Int>()
    val seenJob = launch { conflated.collect { seen.add(it) } }
    awaitCondition("conflated subscription") { conflated.subscriptionCount.value == 1 }
    conflated.value = 0
    conflated.value = 1
    awaitCondition("conflated drain") { seen.size >= 2 }
    delay(20)
    println(seen)
    seenJob.cancel()
    awaitCondition("conflated unsubscribe") { conflated.subscriptionCount.value == 0 }
    println(conflated.subscriptionCount.value)

    // Four worker threads contending on one flow must not lose an increment:
    // every successful update adds exactly 1, so the final value equals the
    // total number of operations performed.
    val shared = MutableStateFlow(0)
    val increments = 250
    val workers = List(4) { Worker.start(name = "inc-$it") }
    val futures = workers.mapIndexed { index, worker ->
        worker.execute(TransferMode.UNSAFE, { Work(shared, index, increments) }) { work ->
            runIncrements(work)
        }
    }
    var performed = 0
    for (future in futures) performed += future.result
    println(performed)
    println(shared.value)
    workers.forEach { it.requestTermination(true) }

    // Emissions from another thread must wake a suspended collector in write
    // order; conflation may drop middle values but the tail is always latest.
    val hot = MutableStateFlow(0)
    val received = mutableListOf<Int>()
    val collectJob = launch { hot.collect { received.add(it) } }
    awaitCondition("hot subscription") { hot.subscriptionCount.value == 1 }
    val emitter = Worker.start()
    val emitted = emitter.execute(TransferMode.UNSAFE, { hot }) { flow ->
        emitRange(flow)
    }
    println(emitted.result)
    awaitCondition("hot drain") { (received.lastOrNull() ?: -1) == 200 }
    println(received.first())
    println(received.last())
    var monotonic = true
    for (i in 1 until received.size) {
        if (received[i] <= received[i - 1]) monotonic = false
    }
    println(monotonic)
    collectJob.cancel()
    awaitCondition("hot unsubscribe") { hot.subscriptionCount.value == 0 }
    println(hot.subscriptionCount.value)
    emitter.requestTermination(true)
}
