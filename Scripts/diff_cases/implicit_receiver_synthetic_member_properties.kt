// KUU-1451: bare `lastIndex`/`indices` on a scope-function implicit receiver
// must materialize `this` — the same value the explicit `receiver.prop`
// member call produces.
fun main() {
    val list = listOf(1, 2, 3)
    println(list.run { lastIndex })
    println(list.run { indices })
    list.apply { println(lastIndex) }
    with(list) {
        println(lastIndex)
        println(indices)
    }

    val array = arrayOf("a", "b", "c")
    println(array.run { lastIndex })
    println(array.run { indices })
    with(array) {
        println(lastIndex)
        println(indices)
    }

    val ints = intArrayOf(4, 5, 6)
    println(ints.run { lastIndex })
    println(ints.run { indices })
    with(ints) {
        println(lastIndex)
        println(indices)
    }

    val mutable = mutableListOf(7, 8)
    println(mutable.run { lastIndex })
    with(mutable) { println(indices) }
}
