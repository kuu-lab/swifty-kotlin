// KUU-3075: an iterator {}/sequence {} builder that captures a class member
// must keep its SequenceScope receiver as the implicit receiver for
// yield/yieldAll even when the enclosing `this` is also captured.
class Grid(val w: Int, val h: Int) {
    fun seq(): Sequence<Int> = sequence {
        yield(w)
        for (x in 0 until h) yield(x)
    }

    fun it(): Iterator<Int> = iterator {
        yield(w)
        yieldAll(listOf(h, w))
    }

    fun viaOuterCall(): Iterator<Int> = iterator {
        yield(compute())
    }

    private fun compute(): Int = w * 2
}

fun main() {
    val g = Grid(3, 2)
    g.seq().forEach { println(it) }
    g.it().forEach { println(it) }
    g.viaOuterCall().forEach { println(it) }
}
