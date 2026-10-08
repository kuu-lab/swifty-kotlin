// yieldAll's first iterator probe is catchable by the producer. Failures after
// delegation begins belong to the consumer. Iterator acquisition must run once.
class YieldAllSource : Iterable<Int>, Sequence<Int> {
    var calls: Int = 0

    override fun iterator(): Iterator<Int> {
        calls += 1
        if (calls == 1) throw IllegalArgumentException("acquire")
        return listOf(9).iterator()
    }
}

class YieldAllProbe : Iterator<Int> {
    var probes: Int = 0
    var consumed: Boolean = false

    override fun hasNext(): Boolean {
        probes += 1
        if (probes == 2) throw IllegalArgumentException("probe")
        return !consumed
    }

    override fun next(): Int {
        consumed = true
        return 28
    }
}

fun main() {
    val initial = sequence<Int> {
        throw IllegalArgumentException("initial")
    }
    val caught = sequence<Int> {
        yield(1)
        try {
            yieldAll(initial)
        } catch (error: IllegalArgumentException) {
            yield(2)
        }
    }
    println("initial:${caught.toList()}")

    val later = sequence<Int> {
        yield(9)
        throw IllegalArgumentException("later")
    }
    val delegated = sequence<Int> {
        yield(1)
        try {
            yieldAll(later)
        } catch (error: IllegalArgumentException) {
            yield(2)
        }
    }.iterator()
    println("later:first=${delegated.next()}")
    println("later:second=${delegated.next()}")
    try {
        delegated.hasNext()
    } catch (error: IllegalArgumentException) {
        println("later:error=${error.message}")
    }

    val source = YieldAllSource()
    val acquired = sequence<Int> {
        try {
            yieldAll(source as Iterable<Int>)
        } catch (error: IllegalArgumentException) {
            yield(2)
        }
    }
    println("acquire:${acquired.toList()}")
    println("acquire:calls=${source.calls}")

    val probed = sequence<Int> { yieldAll(YieldAllProbe()) }.iterator()
    println("probe:first=${probed.next()}")
    try {
        probed.hasNext()
    } catch (error: IllegalArgumentException) {
        println("probe:error=${error.message}")
    }
}
