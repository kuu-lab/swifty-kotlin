// KUU-3075: sequence{}/iterator{} builder lambdas capturing an enclosing
// class member used to panic at runtime — the captured `this` overwrote the
// SequenceScope receiver, so yield() got an invalid builder handle.
class Grid(val w: Int, val name: String) {
    fun it(): Iterator<Int> = iterator { for (x in 0 until w) yield(x) }
    fun seq(): Sequence<Int> = sequence { for (x in 0 until w) yield(x + 1) }
    fun seqAll(): Sequence<Int> = sequence { yield(w); yieldAll(listOf(9, 8)) }
    fun named(): Sequence<String> = sequence { yield(name); yield(this@Grid.name) }
    fun iteratorOp() = object : Iterable<Int> {
        override fun iterator(): Iterator<Int> = iterator { yield(w); yield(w + 1) }
    }
}

fun main() {
    val g = Grid(2, "g")
    g.it().forEach { println(it) }
    println(g.seq().toList())
    println(g.seqAll().toList())
    println(g.named().toList())
    println(g.iteratorOp().toList())
    val lim = 3
    println(sequence { for (x in 0 until lim) yield(x) }.toList())
}
