@file:Suppress("DEPRECATION")
import kotlinx.atomicfu.*
import kotlinx.atomicfu.atomic as createAtomic
import kotlinx.atomicfu.atomic

class EqualValue(val number: Int) {
    override fun equals(other: Any?): Boolean = other is EqualValue && other.number == number
    override fun hashCode(): Int = number
}

fun main() {
    val int = createAtomic(Int.MAX_VALUE)
    println(int.incrementAndGet())
    println(int.getAndAdd(2))
    println(int.value)
    int.lazySet(4)
    println(int.compareAndSet(4, 7))
    println(int.getAndSet(9))
    println(int.value)
    val long = atomic(Long.MAX_VALUE)
    println(long.incrementAndGet())
    println(long.getAndAdd(2L))
    println(long.value)
    val bool = atomic(false)
    println(bool.compareAndSet(false, true))
    println(bool.getAndSet(false))
    println(bool.value)
    val nullable = atomic<Int?>(null)
    println(nullable.getAndSet(5))
    println(nullable.getAndSet(null))
    println(nullable.value)
    val first = EqualValue(1)
    val equal = EqualValue(1)
    val ref = atomic(first)
    println(ref.compareAndSet(equal, EqualValue(2)))
    println(ref.value === first)
    println(ref.compareAndSet(first, equal))
    println(ref.getAndSet(first) === equal)
    long.lazySet(1L)
    println(long.updateAndGet { it + 2L })
    bool.update { !it }
    println(bool.getAndUpdate { !it })
    println(bool.updateAndGet { !it })
    nullable.update { (it ?: 0) + 1 }
    println(nullable.getAndUpdate { (it ?: 0) + 1 })
    println(nullable.updateAndGet { (it ?: 0) + 1 })
    val ints = AtomicIntArray(2)
    val longs = AtomicLongArray(2)
    val bools = AtomicBooleanArray(2)
    val refs = atomicArrayOfNulls<String>(2)
    println(ints[0] === ints[0] && longs[0] === longs[0] && bools[0] === bools[0] && refs[0] === refs[0])
    println(ints[0] !== ints[1] && refs[0] !== refs[1])
    try { ints[2] } catch (e: IndexOutOfBoundsException) { println("array-upper") }
    try { refs[-1] } catch (e: IndexOutOfBoundsException) { println("array-negative") }
    try { AtomicBooleanArray(-1) } catch (e: RuntimeException) { println("array-size") }
    ints[0].value = 3
    ints[0].incrementAndGet()
    longs[0].value = 5L
    bools[0].value = true
    refs[0].value = "held"
    println("${ints.size}:${ints[0].value}:${ints[1].value}:${longs[0].value}:${bools[0].value}:${refs[0].value}:${refs[1].value}")
    var delegated by atomic(11)
    delegated += 1
    println(delegated)
    var retryCalls = 0
    val retry = atomic(0)
    retry.update { old ->
        retryCalls++
        if (retryCalls == 1) retry.value = 4
        old + 1
    }
    println("${retry.value}:$retryCalls")
    println(retry.getAndUpdate { it + 2 })
    println(retry.updateAndGet { it + 3 })
    var traceArguments = 0
    val traced = atomic(7, Trace(size = run { traceArguments++; 32 },
        format = run { traceArguments++; TraceFormat() }))
    println("${traced.value}:$traceArguments")
    var events = 0
    val trace = Trace()
    trace { events++; "event" }
    trace.named("named").invoke { events++; "event" }
    println("${trace === TraceBase.None}:$events")
    println(TraceFormat { index, event -> "$event/$index" }.format(2, "x"))
    println(traceFormatDefault.format(3, "y"))
}
