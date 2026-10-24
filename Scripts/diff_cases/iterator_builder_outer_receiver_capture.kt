// KUU-3075: iterator {}/sequence {} builder blocks that capture the outer
// class receiver used to panic at runtime (__kk_sequence_builder_yield got an
// invalid builder handle). Restoring the packed/raw `this` capture rebound the
// implicit receiver to the captured class handle instead of keeping the
// builder's SequenceScope receiver param.
class Grid(val w: Int) {
    fun it(): Iterator<Int> = iterator {
        for (x in 0 until w) yield(x)
    }

    fun seq(): Sequence<Int> = sequence {
        for (x in 0 until w) yield(x * 10)
    }

    fun labeled(): Iterator<Int> = iterator {
        yield(this@Grid.w)
        yield(bump())
    }

    private fun bump(): Int = w + 1

    fun multi(offset: Int): Iterator<Int> {
        val base = offset
        return iterator {
            yield(w + base)
            yield(w + base + 1)
        }
    }

    operator fun iterator(): Iterator<Int> = iterator {
        yield(w)
        yield(w + 1)
    }
}

fun main() {
    for (x in Grid(2).it()) println(x)
    for (x in Grid(2).seq()) println(x)
    val l = Grid(5).labeled()
    while (l.hasNext()) println(l.next())
    for (x in Grid(10).multi(100)) println(x)
    for (v in Grid(7)) println(v)
}
