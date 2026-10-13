import recordingproducer.session as newSession
import recordingproducer.counter
import recordingproducer.bump
import recordingproducer.appendHidden
import kswiftk.atomicfu.RecordingAtomicInt
import kswiftk.atomicfu.RecordingTrace
fun main() {
    val trace: RecordingTrace = newSession()
    val atomic: RecordingAtomicInt = counter(trace)
    check(bump(atomic) == 1)
    appendHidden(trace)
    check(atomic.compareAndSet(1, 2))
    val saved = trace.snapshot()
    check(saved.size == 3 && saved[0].event == "counter.incAndGet():1")
    check(saved[1].event.toString() == "hidden" && saved[2].event == "counter.CAS(1, 2)")
    println(trace.toString())
    atomic.value = 3
    check(saved.size == 3 && trace.snapshot().size == 4)
    println("consumer-state:${atomic.value}")
}
