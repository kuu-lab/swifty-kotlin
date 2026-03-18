fun main() {
    // STDLIB-543: firstOrNull
    val list = listOf(1, 2, 3)
    println(list.firstOrNull())
    println(emptyList<Int>().firstOrNull())

    // STDLIB-544: lastOrNull
    println(list.lastOrNull())
    println(emptyList<Int>().lastOrNull())

    // STDLIB-545: getOrNull
    println(list.getOrNull(0))
    println(list.getOrNull(5))
    println(emptyList<Int>().getOrNull(0))
}
