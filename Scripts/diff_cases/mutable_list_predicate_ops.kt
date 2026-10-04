fun mutateCollection(values: MutableCollection<Int>) {
    println(values.add(9))
    println(values.remove(2))
    println(values.remove(99))
    println(values.addAll(listOf(7, 8)))
    println(values.removeAll(listOf(7)))
    println(values.retainAll(listOf(1, 8, 9)))
    println(values.isEmpty())
    values.clear()
    println(values.isEmpty())
}

fun main() {
    val values = mutableListOf(1, 2, 3, 4, 5)
    println(values.removeIf { it % 2 == 0 })
    println(values)
    println(values.removeIf { it > 100 })
    println(values)

    values.replaceAll { it * 10 }
    println(values)

    values.fill(7)
    println(values)

    val empty = mutableListOf<Int>()
    println(empty.removeIf { true })
    empty.replaceAll { it + 1 }
    empty.fill(1)
    println(empty)

    val words = mutableListOf("alpha", "beta", "gamma")
    words.replaceAll { it.uppercase() }
    println(words)
    println(words.removeIf { it.startsWith("B") })
    println(words)

    mutateCollection(mutableListOf(1, 2, 3))
    mutateCollection(mutableSetOf(1, 2, 3))
}
