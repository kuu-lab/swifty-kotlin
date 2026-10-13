class RetryNextIterator : Iterator<Int> {
    var calls = 0
    override fun hasNext(): Boolean = calls < 2
    override fun next(): Int {
        calls += 1
        if (calls == 1) throw IllegalArgumentException("retry next")
        return 26
    }
}

class RetryProbeIterator : Iterator<Int> {
    var probes = 0
    var consumed = false
    override fun hasNext(): Boolean {
        probes += 1
        if (probes == 2) throw IllegalArgumentException("retry probe")
        return !consumed
    }
    override fun next(): Int { consumed = true; return 28 }
}

fun main() {
    println(iterator<Int> { yieldAll(listOf(1, 2, 3)) }.asSequence().toList())
    println(iterator<Int> { yieldAll(1..3) }.asSequence().toList())
    println(iterator<Int> { yieldAll(4..3); yield(9) }.asSequence().toList())
    println(iterator<Int> {
        yield(0)
        yieldAll(emptyList<Int>())
        yieldAll(listOf(1, 2, 3))
        yieldAll(sequenceOf(4, 5))
        yieldAll(iterator<Int> { yield(6); yield(7) })
        yield(8)
    }.asSequence().toList())

    println(iterator<String?> { yieldAll(listOf(null, "ok")); yield(null) }.asSequence().toList())
    println(iterator<Int> {
        val custom = object : Iterable<Int> {
            override fun iterator(): Iterator<Int> = listOf(20, 21).iterator()
        }
        yieldAll(custom)
        yield(22)
    }.asSequence().toList())
    println(iterator<Int> {
        val acquisitionThrows = object : Iterable<Int> {
            override fun iterator(): Iterator<Int> = throw IllegalArgumentException("iterator")
        }
        try { yieldAll(acquisitionThrows) } catch (e: IllegalArgumentException) { yield(24) }
        yield(25)
    }.asSequence().toList())
    println(iterator<Int> {
        val custom = object : Sequence<Int> {
            override fun iterator(): Iterator<Int> = listOf(30, 31).iterator()
        }
        yieldAll(custom)
        yield(32)
    }.asSequence().toList())
    val nextFailure = iterator<Int> {
        val nextThrows = object : Iterator<Int> {
            override fun hasNext(): Boolean = true
            override fun next(): Int = throw IllegalArgumentException("next")
        }
        yieldAll(nextThrows)
        yield(23)
    }
    println(nextFailure.hasNext())
    try { nextFailure.next() } catch (e: IllegalArgumentException) { println(e.message) }
    println(nextFailure.hasNext())

    val recoverNext = iterator<Int> { yieldAll(RetryNextIterator()); yield(27) }
    try { recoverNext.next() } catch (e: IllegalArgumentException) { println(e.message) }
    println(recoverNext.asSequence().toList())

    val recoverProbe = iterator<Int> { yieldAll(RetryProbeIterator()); yield(29) }
    println(recoverProbe.next())
    try { recoverProbe.hasNext() } catch (e: IllegalArgumentException) { println(e.message) }
    println(recoverProbe.asSequence().toList())

    val lazy = iterator<Int> {
        println("start")
        yieldAll(iterator<Int> {
            println("one")
            yield(1)
            println("two")
            yield(2)
            println("end")
        })
        println("after")
        yield(3)
    }
    println("checkpoint")
    println(lazy.hasNext())
    println(lazy.hasNext())
    println("checkpoint")
    println(lazy.next())
    println("checkpoint")
    println(lazy.next())
    println("checkpoint")
    println(lazy.next())
    println("checkpoint")
    println(lazy.hasNext())

    val caught = iterator<Int> {
        try {
            yieldAll(iterator<Int> { if (false) yield(0); throw IllegalArgumentException("initial") })
        } catch (e: IllegalArgumentException) {
            yield(10)
        }
        yield(11)
    }
    println(caught.asSequence().toList())
    val failed = iterator<Int> {
        try {
            yieldAll(iterator<Int> { yield(12); throw IllegalArgumentException("later") })
        } catch (e: IllegalArgumentException) {
            yield(13)
        }
        yield(14)
    }
    println(failed.next())
    try { failed.hasNext() } catch (e: IllegalArgumentException) { println(e.message) }
    try { failed.hasNext() } catch (e: IllegalStateException) { println("failed") }
}
