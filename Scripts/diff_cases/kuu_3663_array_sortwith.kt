fun checkSortWithBounds(from: Int, to: Int) {
    val array = arrayOf(3, 1, 2)
    try {
        array.sortWith(naturalOrder(), from, to)
        println("accepted")
    } catch (e: IndexOutOfBoundsException) {
        println("bounds")
    } catch (e: IllegalArgumentException) {
        println("order")
    }
    println(array.toList())
}

fun main() {
    val a = arrayOf(3, 1, 2)
    val alias = a
    a.sortWith(compareByDescending { it })
    println(alias.toList())

    val words = arrayOf("pear", "fig", "apple")
    words.sortWith(compareBy<String> { it.length })
    println(words.toList())

    val ascending = arrayOf(3, 1, 2)
    ascending.sortWith(naturalOrder())
    println(ascending.toList())
    ascending.sortWith(reverseOrder())
    println(ascending.toList())

    val lambdaSorted = arrayOf(2, 3, 1)
    lambdaSorted.sortWith { x, y -> x - y }
    println(lambdaSorted.toList())

    val ranged = arrayOf(3, 1, 2, 5, 4)
    ranged.sortWith(compareByDescending { it }, 1, 4)
    println(ranged.toList())
    ranged.sortWith(naturalOrder(), toIndex = 3, fromIndex = 0)
    println(ranged.toList())

    val stable = arrayOf("bb", "a", "cc", "d", "ee")
    stable.sortWith(compareBy<String> { it.length })
    println(stable.toList())

    val empty = emptyArray<Int>()
    empty.sortWith(naturalOrder())
    empty.sortWith(naturalOrder(), 0, 0)
    println(empty.toList())
    val singleton = arrayOf(42)
    singleton.sortWith(reverseOrder())
    singleton.sortWith(naturalOrder(), 0, 1)
    println(singleton.toList())

    checkSortWithBounds(2, 1)
    checkSortWithBounds(-1, 2)
    checkSortWithBounds(0, 4)
    checkSortWithBounds(3, 3)
}
