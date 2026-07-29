class Counter(var value: Int) {
    fun compareAndSet(expected: Int, newValue: Int): Boolean {
        if (value != expected) return false
        value = newValue
        return true
    }
}

class Flag(var raised: Boolean)

// Same simple name as Counter's member but an unrelated receiver: an
// unqualified call from a Counter extension body must still bind Counter's
// member instead of failing overload resolution on this candidate.
fun Flag.compareAndSet(expected: Boolean, newValue: Boolean): Boolean {
    if (raised != expected) return false
    raised = newValue
    return true
}

fun Counter.getAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = value
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

fun main() {
    val counter = Counter(7)
    println(counter.getAndUpdate { it * 3 })
    println(counter.value)

    val flag = Flag(false)
    println(flag.compareAndSet(false, true))
    println(flag.raised)
}
