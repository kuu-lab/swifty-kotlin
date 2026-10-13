@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
import kswiftk.atomicfu.*
import kotlinx.atomicfu.Trace
import kotlinx.atomicfu.TraceBase
import kotlinx.atomicfu.TraceFormat
import kotlinx.atomicfu.atomic
import kotlinx.atomicfu.named
import kotlin.native.runtime.GC

private var defaultCalls = 0
private fun defaultEvent(): String { defaultCalls += 1; return "default" }
private fun appendDefault(trace: RecordingTrace, event: Any = defaultEvent()) { trace.append(event) }
private var namedCalls = 0
private class NamedEvent { override fun toString(): String { namedCalls += 1; return "payload" } }
private fun rows(trace: RecordingTrace): String = trace.snapshot().joinToString("|") { "${it.index}=${it.event}" }

fun main() {
    val trace = RecordingTrace(3)
    check(trace.capacity == 4)
    trace.append("a", "b")
    val saved = trace.snapshot()
    trace.append("c", "d", "e")
    check(rows(trace) == "1=b|2=c|3=d|4=e")
    check(saved.size == 2 && saved[0].index == 0 && saved[0].event == "a")
    println("ring:${rows(trace)}")
    val named = trace.named("outer").named("inner")
    named.append(NamedEvent())
    check(namedCalls == 1 && rows(trace) == "2=c|3=d|4=e|5=outer.inner.payload")
    check(named.snapshot()[3].event == "outer.inner.payload")
    println("named:${rows(trace)}")
    appendDefault(trace)
    appendDefault(trace, "explicit")
    check(defaultCalls == 1)
    println("default:$defaultCalls")
    val one = RecordingTrace(1)
    one.append("a", "b", "c", "d")
    check(rows(one) == "3=d")
    println("single:${rows(one)}")
    var rejected = 0
    for (size in listOf(Int.MIN_VALUE, -1, 0, 1_048_577, Int.MAX_VALUE)) {
        try { RecordingTrace(size); error("invalid size accepted") }
        catch (expected: IllegalArgumentException) { rejected += 1 }
    }
    check(rejected == 5)
    println("invalid-size:$rejected")
    val largest = RecordingTrace(1_048_576)
    check(largest.capacity == 1_048_576 && largest.snapshot().isEmpty())
    println("maximum:${largest.capacity}")
    val event = NamedEvent()
    val gcTrace = RecordingTrace(1)
    gcTrace.append(event)
    GC.collect()
    check(gcTrace.snapshot()[0].event === event)
    gcTrace.append("replacement")
    GC.collect()
    check(gcTrace.snapshot()[0].event == "replacement")
    // This is live identity/replacement, not a registered-box reclamation proof.
    println("gc-live-replacement")
    val untouched = RecordingTrace()
    val ordinary = atomic(0, untouched)
    ordinary.incrementAndGet()
    check(untouched.snapshot().isEmpty() && ordinary.value == 1)
    check(Trace(-1) === TraceBase.None && TraceBase.None.named("none") === TraceBase.None)
    println("native-none")
    var formatCalls = 0
    val formatted = RecordingTrace(2, TraceFormat { index, value ->
        formatCalls += 1
        "$index=$value"
    })
    formatted.append("x", "y")
    check(formatCalls == 0)
    check(formatted.toString() == "0=x\n1=y" && formatCalls == 2)
    println("format:$formatCalls")
    val virtual = RecordingTrace(4)
    val base: TraceBase = virtual
    var invokes = 0
    base { invokes += 1; "invoke" }
    check(invokes == 1 && rows(virtual) == "0=invoke")
    base.append("a", "b")
    base.append("c", "d", "e")
    base.append("f", "g", "h", "i")
    check(rows(virtual) == "6=f|7=g|8=h|9=i")
    println("virtual:$invokes:${rows(virtual)}")
}
