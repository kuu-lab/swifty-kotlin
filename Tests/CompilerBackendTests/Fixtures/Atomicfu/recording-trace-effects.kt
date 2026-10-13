@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
import kswiftk.atomicfu.*
import kotlinx.atomicfu.TraceBase
import kotlinx.atomicfu.TraceFormat
private var calls = 0
private class FailingEvent { override fun toString(): String { calls += 1; throw IllegalArgumentException("event") } }
private class EqualEvent {
    override fun equals(other: Any?): Boolean = other is EqualEvent
    override fun hashCode(): Int = 1
    override fun toString(): String = "equal"
}
private fun event(): Any { calls += 1; return "event" }
fun main() {
    TraceBase.None { event() }
    TraceBase.None.append(event(), event(), event(), event())
    check(calls == 5)
    println("none-callbacks:$calls")
    val payload = FailingEvent()
    val none = recordingAtomic<FailingEvent?>(null, TraceBase.None)
    none.value = payload; none.lazySet(payload)
    check(none.getAndSet(null) === payload)
    check(none.compareAndSet(null, payload) && calls == 5)
    println("none-no-stringify:$calls")
    val trace = RecordingTrace()
    val ref = recordingAtomic<FailingEvent?>(null, trace)
    try { ref.value = payload; error("event failure lost") }
    catch (expected: IllegalArgumentException) { check(expected.message == "event") }
    check(ref.value === payload && trace.snapshot().isEmpty() && calls == 6)
    check(!ref.compareAndSet(null, null) && calls == 6)
    println("postcommit-failure:$calls")
    try { ref.compareAndSet(payload, null); error("successful CAS failure lost") }
    catch (expected: IllegalArgumentException) { check(expected.message == "event") }
    check(ref.value == null && trace.snapshot().isEmpty() && calls == 7)
    println("cas-postcommit:$calls")
    try { trace { throw IllegalStateException("callback") }; error("callback failure lost") }
    catch (expected: IllegalStateException) { check(expected.message == "callback") }
    check(trace.snapshot().isEmpty())
    println("invoke-failure")
    try { trace.named("n").append("first", payload); error("named failure lost") }
    catch (expected: IllegalArgumentException) { check(expected.message == "event") }
    check(trace.snapshot().isEmpty() && calls == 8)
    trace.append("recovered")
    check(trace.snapshot().size == 1)
    println("named-batch-failure:$calls")
    var formats = 0
    val failing = RecordingTrace(format = TraceFormat { _, _ ->
        formats += 1; throw IllegalStateException("format")
    })
    failing.append("raw")
    check(formats == 0)
    try { failing.toString(); error("format failure lost") }
    catch (expected: IllegalStateException) { check(expected.message == "format") }
    check(failing.snapshot().size == 1 && formats == 1)
    failing.append("after")
    check(failing.snapshot().size == 2)
    println("format-failure:$formats")
    var current: RecordingTrace? = null
    var callbacks = 0
    val reentrant = RecordingTrace(format = TraceFormat { _, value ->
        if (callbacks == 0) { callbacks += 1; current!!.append("callback") }
        value.toString()
    })
    current = reentrant
    reentrant.append("base")
    check(reentrant.toString() == "base" && reentrant.snapshot().size == 2)
    check(reentrant.toString() == "base\ncallback" && callbacks == 1)
    println("format-reentry:$callbacks")
    val defaultAtomic = recordingAtomic(3)
    val defaultTrace = defaultAtomic.trace as RecordingTrace
    check(defaultTrace.capacity == 32 && defaultTrace.snapshot().isEmpty())
    check(defaultAtomic.incrementAndGet() == 4)
    check(defaultTrace.snapshot().size == 1 && defaultAtomic.trace === defaultTrace)
    println("default-factory:1")
    val identityTrace = RecordingTrace()
    val first = EqualEvent(); val equalButDistinct = EqualEvent(); val updated = EqualEvent()
    check(first == equalButDistinct && first !== equalButDistinct)
    val identity = recordingAtomic(first, identityTrace)
    check(!identity.compareAndSet(equalButDistinct, updated) && identityTrace.snapshot().isEmpty())
    check(identity.compareAndSet(first, updated) && identity.value === updated)
    check(identityTrace.snapshot().size == 1 && identityTrace.snapshot()[0].event == "CAS(equal, equal)")
    println("identity-success-only:1")
    recordingExceptionSupplement()
}

// Only this test file suppresses the upstream TraceBase internal constructor.
// It does not widen product visibility or the separate Core negative inputs.
private class ThrowingAppendTrace : TraceBase() {
    var appendCalls = 0
    var lastEvent: Any? = null
    override fun append(event: Any) {
        appendCalls += 1
        lastEvent = event
        throw IllegalStateException("append")
    }
}

private fun recordingExceptionSupplement() {
    val rejected = ThrowingAppendTrace()
    val committed = recordingAtomic(0, rejected)
    try { committed.value = 1; error("append failure lost") }
    catch (expected: IllegalStateException) { check(expected.message == "append") }
    check(committed.value == 1 && rejected.appendCalls == 1 && rejected.lastEvent == "set(1)")
    check(!committed.compareAndSet(0, 2) && rejected.appendCalls == 1)
    try { committed.compareAndSet(1, 2); error("CAS append failure lost") }
    catch (expected: IllegalStateException) { check(expected.message == "append") }
    check(committed.value == 2 && rejected.appendCalls == 2 && rejected.lastEvent == "CAS(1, 2)")
    try { committed.getAndSet(3); error("exchange append failure lost") }
    catch (expected: IllegalStateException) { check(expected.message == "append") }
    check(committed.value == 3 && rejected.appendCalls == 3 && rejected.lastEvent == "getAndSet(3):2")
    println("custom-append-postcommit:${rejected.appendCalls}:${committed.value}")

    val delayed = RecordingTrace(1)
    val delayedEvent = FailingEvent()
    val beforeCalls = calls
    delayed.append(delayedEvent)
    val saved = delayed.snapshot()
    check(calls == beforeCalls && saved.size == 1 && saved[0].event === delayedEvent)
    println("unnamed-before-format:${calls - beforeCalls}:${saved.size}")
    try { delayed.toString(); error("delayed event failure lost") }
    catch (expected: IllegalArgumentException) { check(expected.message == "event") }
    val retained = delayed.snapshot()
    check(calls == beforeCalls + 1 && retained.size == 1 && retained[0].event === delayedEvent)
    check(saved[0].event === delayedEvent)
    println("unnamed-format-throw:${calls - beforeCalls}:${retained.size}")
    delayed.append("replacement")
    val replacement = delayed.snapshot()
    check(calls == beforeCalls + 1 && replacement.size == 1)
    check(replacement[0].index == 1 && replacement[0].event == "replacement")
    check(saved[0].index == 0 && saved[0].event === delayedEvent)
    check(delayed.toString() == "1: replacement" && calls == beforeCalls + 1)
    println("unnamed-after-replacement:${calls - beforeCalls}:${replacement[0].event}")
}
