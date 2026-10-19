fun <T> jortSort(a: Array<T>): Boolean {
    val b = a.copyOf()
    b.sort()
    return true
}

fun <T> sortedCopy(a: Array<T>): List<T> {
    val b = a.copyOf()
    b.sort()
    return b.toList()
}

fun <T> partialSortedCopy(a: Array<T>, fromIndex: Int, toIndex: Int): List<T> {
    val b = a.copyOf()
    b.sort(fromIndex, toIndex)
    return b.toList()
}

fun main() {
    val a = arrayOf(3, 1, 2)
    println(jortSort(a))
    println(sortedCopy(a))

    val b = arrayOf("cherry", "apple", "banana")
    println(jortSort(b))
    println(sortedCopy(b))

    val c = arrayOf(5, 9, 2, 1, 7)
    println(partialSortedCopy(c, 1, 4))
}
