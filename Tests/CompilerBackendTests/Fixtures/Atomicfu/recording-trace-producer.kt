package recordingproducer
import kswiftk.atomicfu.*
private class HiddenEvent(private val text: String) { override fun toString(): String = text }
public fun session(): RecordingTrace = RecordingTrace(4)
public fun counter(trace: RecordingTrace): RecordingAtomicInt = recordingAtomic(0, trace.named("counter"))
public inline fun bump(counter: RecordingAtomicInt): Int = counter.incrementAndGet()
public fun appendHidden(trace: RecordingTrace) { trace.append(HiddenEvent("hidden")) }
