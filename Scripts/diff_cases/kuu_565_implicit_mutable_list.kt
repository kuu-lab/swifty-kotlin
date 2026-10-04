fun main() {
    println(mutableListOf(1, 2, 3).apply { remove(1) })
    println(mutableListOf(10, 20, 30).apply { removeAll { it > 15 } })
    println(mutableListOf(10, 20, 30).apply { retainAll { it > 15 } })
    println(mutableListOf(1, 2, 3, 4).apply {
        val iter = iterator()
        while (iter.hasNext()) {
            if (iter.next() % 2 == 0) iter.remove()
        }
    })

    val list = mutableListOf(1, 2, 3)
    with(list) { remove(3) }
    println(list)
    list.run { removeAll { it == 1 } }
    println(list)
}
