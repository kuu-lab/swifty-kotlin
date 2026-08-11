fun main() {
    val values = listOf(10, 20, 30)

    values.iterator().forEach { println(it) }

    for (iv in values.iterator().withIndex()) {
        println(iv.index.toString() + ":" + iv.value.toString())
    }

    val empty = listOf<String>().iterator()
    empty.forEach { println(it) }
    for (iv in empty.withIndex()) {
        println(iv.index.toString() + ":" + iv.value.toString())
    }

    println("done")
}
