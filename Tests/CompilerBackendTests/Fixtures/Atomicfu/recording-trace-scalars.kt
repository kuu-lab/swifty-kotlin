import kswiftk.atomicfu.*
private fun messages(trace: RecordingTrace): String = trace.snapshot().joinToString("|") { it.event.toString() }
fun main() {
    val ti = RecordingTrace(32)
    val i = recordingAtomic(0, ti.named("i"))
    i.value = 1; i.lazySet(2)
    check(!i.compareAndSet(1, 4)); check(i.compareAndSet(2, 3))
    check(i.getAndSet(4) == 3); check(i.getAndIncrement() == 4)
    check(i.getAndDecrement() == 5); check(i.getAndAdd(2) == 4)
    check(i.addAndGet(-1) == 5); check(i.incrementAndGet() == 6)
    check(i.decrementAndGet() == 5); i += 3; i -= 2
    var delegated by i
    check(delegated == 6); delegated = 7
    i.update { it + 1 }; check(i.getAndUpdate { it + 1 } == 8)
    check(i.updateAndGet { it + 1 } == 10)
    val intEvents = "i.set(1)|i.lazySet(2)|i.CAS(2, 3)|i.getAndSet(4):3|i.getAndInc():4|i.getAndDec():5|i.getAndAdd(2):4|i.addAndGet(-1):5|i.incAndGet():6|i.decAndGet():5|i.getAndAdd(3):5|i.getAndAdd(-2):8|i.set(7)|i.CAS(7, 8)|i.CAS(8, 9)|i.CAS(9, 10)"
    check(messages(ti) == intEvents && ti.snapshot().size == 16)
    println("int:$intEvents")
    val tl = RecordingTrace(32)
    val l = recordingAtomic(0L, tl.named("l"))
    l.value = 1L; l.lazySet(2L)
    check(!l.compareAndSet(1L, 4L)); check(l.compareAndSet(2L, 3L))
    check(l.getAndSet(4L) == 3L); check(l.getAndIncrement() == 4L)
    check(l.getAndDecrement() == 5L); check(l.getAndAdd(2L) == 4L)
    check(l.addAndGet(-1L) == 5L); check(l.incrementAndGet() == 6L)
    check(l.decrementAndGet() == 5L); l += 3L; l -= 2L
    l.update { it + 1L }; check(l.getAndUpdate { it + 1L } == 7L)
    check(l.updateAndGet { it + 1L } == 9L)
    val longEvents = "l.set(1)|l.lazySet(2)|l.CAS(2, 3)|l.getAndSet(4):3|l.getAndInc():4|l.getAndDec():5|l.getAndAdd(2):4|l.addAndGet(-1):5|l.incAndGet():6|l.decAndGet():5|l.getAndAdd(3):5|l.getAndAdd(-2):8|l.CAS(6, 7)|l.CAS(7, 8)|l.CAS(8, 9)"
    check(messages(tl) == longEvents && tl.snapshot().size == 15)
    println("long:$longEvents")
    val tb = RecordingTrace()
    val b = recordingAtomic(false, tb.named("b"))
    b.value = true; b.lazySet(false)
    check(!b.compareAndSet(true, false)); check(b.compareAndSet(false, true))
    check(b.getAndSet(false)); b.update { !it }
    var booleanDelegate by b
    check(booleanDelegate); booleanDelegate = false
    check(!b.getAndUpdate { !it }); check(!b.updateAndGet { !it })
    val boolEvents = "b.set(true)|b.lazySet(false)|b.CAS(false, true)|b.getAndSet(false):true|b.CAS(false, true)|b.set(false)|b.CAS(false, true)|b.CAS(true, false)"
    check(messages(tb) == boolEvents && tb.snapshot().size == 8)
    println("boolean:$boolEvents")
    val tr = RecordingTrace()
    val r = recordingAtomic<String?>(null, tr.named("r"))
    val a = "a"; val bValue = "b"
    r.value = a; r.lazySet(bValue)
    check(!r.compareAndSet(null, "x")); check(r.compareAndSet(bValue, null))
    check(r.getAndSet(a) == null); r.update { it + "!" }
    check(r.getAndUpdate { "x" } == "a!"); check(r.updateAndGet { null } == null)
    val refEvents = "r.set(a)|r.lazySet(b)|r.CAS(b, null)|r.getAndSet(a):null|r.CAS(a, a!)|r.CAS(a!, x)|r.CAS(x, null)"
    check(messages(tr) == refEvents && tr.snapshot().size == 7 && r.value == null)
    println("ref:$refEvents")
    var reads = 0
    try { i.loop { check(it == 10); reads += 1; throw IllegalArgumentException("stop") } }
    catch (expected: IllegalArgumentException) { check(expected.message == "stop") }
    try { l.loop { check(it == 9L); reads += 1; throw IllegalArgumentException("stop") } }
    catch (expected: IllegalArgumentException) { check(expected.message == "stop") }
    try { b.loop { check(!it); reads += 1; throw IllegalArgumentException("stop") } }
    catch (expected: IllegalArgumentException) { check(expected.message == "stop") }
    try { r.loop { check(it == null); reads += 1; throw IllegalArgumentException("stop") } }
    catch (expected: IllegalArgumentException) { check(expected.message == "stop") }
    check(reads == 4 && messages(ti) == intEvents && messages(tl) == longEvents && messages(tb) == boolEvents && messages(tr) == refEvents)
    println("read-loops:$reads")
    val boundary = RecordingTrace()
    val maximum = recordingAtomic(Int.MAX_VALUE, boundary)
    val minimum = recordingAtomic(Long.MIN_VALUE, boundary)
    check(maximum.incrementAndGet() == Int.MIN_VALUE)
    check(minimum.decrementAndGet() == Long.MAX_VALUE)
    check(messages(boundary) == "incAndGet():-2147483648|decAndGet():9223372036854775807")
    println("wrap:${messages(boundary)}")
    recordingScalarRetrySupplement()
}

// Supplemental source-derived controls. Every first transform performs a real
// mutation, so the following CAS fails; only the retried successful CAS records.
private fun recordingScalarRetrySupplement() {
    val trace = RecordingTrace()
    val scalar = recordingAtomic(0, trace)
    var updateCalls = 0
    scalar.update { current ->
        updateCalls += 1
        if (updateCalls == 1) scalar.value = 10
        current + 1
    }
    check(updateCalls == 2 && scalar.value == 11)
    check(messages(trace) == "set(10)|CAS(10, 11)" && trace.snapshot().size == 2)
    println("retry-update:$updateCalls:${scalar.value}:${trace.snapshot().size}")
    var getCalls = 0
    val previous = scalar.getAndUpdate { current ->
        getCalls += 1
        if (getCalls == 1) scalar.value = 20
        current + 1
    }
    check(getCalls == 2 && previous == 20 && scalar.value == 21)
    check(messages(trace) == "set(10)|CAS(10, 11)|set(20)|CAS(20, 21)" && trace.snapshot().size == 4)
    println("retry-getAndUpdate:$getCalls:$previous:${scalar.value}:${trace.snapshot().size}")
    var newCalls = 0
    val updated = scalar.updateAndGet { current ->
        newCalls += 1
        if (newCalls == 1) scalar.value = 30
        current + 1
    }
    check(newCalls == 2 && updated == 31 && scalar.value == 31)
    check(messages(trace) == "set(10)|CAS(10, 11)|set(20)|CAS(20, 21)|set(30)|CAS(30, 31)" && trace.snapshot().size == 6)
    println("retry-updateAndGet:$newCalls:$updated:${scalar.value}:${trace.snapshot().size}")

    val longTrace = RecordingTrace()
    val long = recordingAtomic(0L, longTrace)
    var longCalls = 0
    val longUpdated = long.updateAndGet { current ->
        longCalls += 1
        if (longCalls == 1) long.value = 10L
        current + 1L
    }
    check(longCalls == 2 && longUpdated == 11L && long.value == 11L)
    check(messages(longTrace) == "set(10)|CAS(10, 11)" && longTrace.snapshot().size == 2)
    println("retry-long:$longCalls:$longUpdated:${longTrace.snapshot().size}")

    val booleanTrace = RecordingTrace()
    val boolean = recordingAtomic(false, booleanTrace)
    var booleanCalls = 0
    boolean.update { current ->
        booleanCalls += 1
        if (booleanCalls == 1) boolean.value = true
        !current
    }
    check(booleanCalls == 2 && !boolean.value)
    check(messages(booleanTrace) == "set(true)|CAS(true, false)" && booleanTrace.snapshot().size == 2)
    println("retry-boolean:$booleanCalls:${boolean.value}:${booleanTrace.snapshot().size}")

    val refTrace = RecordingTrace()
    val ref = recordingAtomic("initial", refTrace)
    var refCalls = 0
    val refPrevious = ref.getAndUpdate { current ->
        refCalls += 1
        if (refCalls == 1) ref.value = "interference"
        current + "!"
    }
    check(refCalls == 2 && refPrevious == "interference" && ref.value == "interference!")
    check(messages(refTrace) == "set(interference)|CAS(interference, interference!)" && refTrace.snapshot().size == 2)
    println("retry-ref:$refCalls:$refPrevious:${ref.value}:${refTrace.snapshot().size}")
}
