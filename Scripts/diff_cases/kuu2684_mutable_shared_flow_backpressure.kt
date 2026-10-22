import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.channels.BufferOverflow

// KUU-2684: MutableSharedFlow implements upstream SharedFlowImpl buffer
// semantics: replay + extraBufferCapacity share one buffer, emit suspends
// under BufferOverflow.SUSPEND when the slowest subscriber keeps it full,
// DROP_OLDEST drops buffered values, DROP_LATEST drops the incoming value.
// This case pins tryEmit results, emit suspension/resume, dropped values a
// lagging collector misses, rendezvous for a zero-capacity flow, the slowest
// of multiple collectors gating emitters, cancellation freeing queued
// emitters, late-subscriber replay, and resetReplayCache against kotlinc
// output.

fun main() = runBlocking {
    // --- constructor validation (upstream messages) ---
    try { MutableSharedFlow<Int>(replay = -1) } catch (e: IllegalArgumentException) { println(e.message) }
    try { MutableSharedFlow<Int>(extraBufferCapacity = -1) } catch (e: IllegalArgumentException) { println(e.message) }
    try { MutableSharedFlow<Int>(0, 0, BufferOverflow.DROP_OLDEST) } catch (e: IllegalArgumentException) { println(e.message) }

    // --- no subscribers: emit never suspends, only replay retained ---
    val free = MutableSharedFlow<Int>(replay = 1, extraBufferCapacity = 4)
    free.emit(1); free.emit(2); free.emit(3)
    println("freeCache=${free.replayCache}")
    println("freeTry=${free.tryEmit(4)}")
    println("freeCache2=${free.replayCache}")

    // --- SUSPEND backpressure ---
    val shared = MutableSharedFlow<Int>(replay = 1, extraBufferCapacity = 1)
    val count = shared.subscriptionCount
    val gate = CompletableDeferred<Unit>()
    val received = mutableListOf<Int>()
    val job = launch {
        shared.collect { v ->
            received.add(v)
            gate.await()
        }
    }
    while (count.value == 0) delay(1)
    shared.emit(1)
    delay(30)
    println("t2=${shared.tryEmit(2)}")
    println("t3=${shared.tryEmit(3)}")
    println("t4=${shared.tryEmit(4)}")
    val done = CompletableDeferred<Unit>()
    launch {
        shared.emit(4)
        done.complete(Unit)
    }
    delay(30)
    println("suspended=${!done.isCompleted}")
    gate.complete(Unit)
    delay(50)
    println("resumed=${done.isCompleted}")
    println("received=$received")
    println("replay=${shared.replayCache}")
    job.cancelAndJoin()

    // --- DROP_OLDEST ---
    val dropping = MutableSharedFlow<Int>(replay = 1, extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val count2 = dropping.subscriptionCount
    val gate2 = CompletableDeferred<Unit>()
    val got2 = mutableListOf<Int>()
    val j2 = launch {
        dropping.collect { v -> got2.add(v); gate2.await() }
    }
    while (count2.value == 0) delay(1)
    dropping.emit(1)
    delay(30)
    println("d2=${dropping.tryEmit(2)}")
    println("d3=${dropping.tryEmit(3)}")
    println("d4=${dropping.tryEmit(4)}")
    println("dCache=${dropping.replayCache}")
    gate2.complete(Unit)
    delay(50)
    println("dropped=$got2")
    j2.cancelAndJoin()

    // --- DROP_LATEST ---
    val latest = MutableSharedFlow<Int>(replay = 1, extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_LATEST)
    val count3 = latest.subscriptionCount
    val gate3 = CompletableDeferred<Unit>()
    val got3 = mutableListOf<Int>()
    val j3 = launch {
        latest.collect { v -> got3.add(v); gate3.await() }
    }
    while (count3.value == 0) delay(1)
    latest.emit(1)
    delay(30)
    println("l2=${latest.tryEmit(2)}")
    println("l3=${latest.tryEmit(3)}")
    println("l4=${latest.tryEmit(4)}")
    println("lCache=${latest.replayCache}")
    gate3.complete(Unit)
    delay(50)
    println("latest=$got3")
    j3.cancelAndJoin()

    // --- rendezvous (zero buffer) ---
    val rdz = MutableSharedFlow<Int>()
    val count4 = rdz.subscriptionCount
    val gate4 = CompletableDeferred<Unit>()
    val got4 = mutableListOf<Int>()
    val j4 = launch { rdz.collect { v -> got4.add(v); gate4.await() } }
    while (count4.value == 0) delay(1)
    delay(20)
    println("rdzTry=${rdz.tryEmit(10)}")
    val rdzDone = CompletableDeferred<Unit>()
    launch { rdz.emit(10); rdzDone.complete(Unit) }
    delay(30)
    println("rdzDone1=${rdzDone.isCompleted}")
    val rdzDone2 = CompletableDeferred<Unit>()
    launch { rdz.emit(11); rdzDone2.complete(Unit) }
    delay(30)
    println("rdzDone2=${rdzDone2.isCompleted}")
    gate4.complete(Unit)
    delay(50)
    println("rdzDone2After=${rdzDone2.isCompleted}")
    println("got4=$got4")
    j4.cancelAndJoin()

    // --- multiple collectors: slowest gates the emitter ---
    val multi = MutableSharedFlow<Int>(replay = 0, extraBufferCapacity = 1)
    val mc = multi.subscriptionCount
    val gateB = CompletableDeferred<Unit>()
    val gotA = mutableListOf<Int>()
    val gotB = mutableListOf<Int>()
    val jobA = launch { multi.collect { v -> gotA.add(v) } }
    val jobB = launch { multi.collect { v -> gateB.await(); gotB.add(v) } }
    while (mc.value < 2) delay(1)
    delay(20)
    multi.emit(1)
    delay(30)
    val mDone = CompletableDeferred<Unit>()
    launch { multi.emit(2); multi.emit(3); mDone.complete(Unit) }
    delay(30)
    println("mBlocked=${!mDone.isCompleted}")
    gateB.complete(Unit)
    delay(60)
    println("mResumed=${mDone.isCompleted}")
    println("gotA=$gotA")
    println("gotB=$gotB")
    println("mCache=${multi.replayCache}")
    jobA.cancelAndJoin()
    jobB.cancelAndJoin()

    // --- cancelled collector unblocks queued emitters ---
    val cx = MutableSharedFlow<Int>(replay = 0, extraBufferCapacity = 1)
    val cc = cx.subscriptionCount
    val gateC = CompletableDeferred<Unit>()
    val gotC = mutableListOf<Int>()
    val cJob = launch { cx.collect { v -> gotC.add(v); gateC.await() } }
    while (cc.value == 0) delay(1)
    cx.emit(1)
    delay(30)
    val cDone = CompletableDeferred<Unit>()
    launch { cx.emit(2); cx.emit(3); cDone.complete(Unit) }
    delay(30)
    println("cBlocked=${!cDone.isCompleted}")
    cJob.cancelAndJoin()
    delay(30)
    println("cResumed=${cDone.isCompleted}")
    println("gotC=$gotC")
    println("cxCache=${cx.replayCache}")

    // --- late subscriber replays cache then goes live ---
    val late = MutableSharedFlow<Int>(replay = 2, extraBufferCapacity = 1)
    late.emit(1); late.emit(2); late.emit(3)
    val gotLate = mutableListOf<Int>()
    val lateDone = CompletableDeferred<Unit>()
    launch {
        late.take(2).collect { v -> gotLate.add(v) }
        lateDone.complete(Unit)
    }
    delay(50)
    println("late=$gotLate")
    println("lateDone=${lateDone.isCompleted}")
    println("lateCache=${late.replayCache}")

    // --- resetReplayCache ---
    val rs = MutableSharedFlow<Int>(replay = 2)
    rs.emit(1); rs.emit(2); rs.emit(3)
    println("beforeReset=${rs.replayCache}")
    rs.resetReplayCache()
    println("afterReset=${rs.replayCache}")
    rs.emit(4)
    println("afterEmit=${rs.replayCache}")
}
