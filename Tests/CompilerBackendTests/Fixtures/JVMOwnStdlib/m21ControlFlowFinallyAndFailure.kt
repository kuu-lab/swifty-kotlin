fun main() {
    var finished = 0
    val values = sequence { try { yield(1); yield(2) } finally { finished++; println("finally") } }
    println(values.first()); println(finished)
    val it = values.iterator(); println(it.next()); println(it.next()); println(finished); println(it.hasNext()); println(finished)
    val broken = iterator<Int> { try { yield(3); throw IllegalArgumentException("boom") } finally { println("failure-finally") } }
    println(broken.next())
    try { broken.hasNext() } catch (e: IllegalArgumentException) { println(e.message) }
    try { broken.hasNext() } catch (e: IllegalStateException) { println(e.message) }
    val caught = sequence {
        try { yield(4); throw IllegalStateException("caught") }
        catch (e: IllegalStateException) { println(e.message); yield(5) }
        finally { println("caught-finally") }
        for (n in 1..4) { if (n == 2) continue; if (n == 4) break; yield(n) }
        return@sequence
    }
    println(caught.toList())
    var outerFinally = false
    val delegated = sequence<Int> { try { yieldAll(sequence<Int> { yield(8); throw IllegalStateException("delegate") }) } finally { outerFinally = true } }.iterator()
    println(delegated.next()); try { delegated.hasNext() } catch (e: IllegalStateException) { println(e.message) }; println(outerFinally)
    println(sequence<Int> { try { yield(6); return@sequence } finally { yield(7) } }.toList())
    var calls = 0
    val endless = sequence { var n = 0; while (true) { calls++; yield(n++) } }
    println(endless.take(3).toList()); println(calls)
}
