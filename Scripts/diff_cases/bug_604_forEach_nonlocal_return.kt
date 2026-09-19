fun listSearch(values: List<Int>): Int {
    values.forEach {
        if (it > 1) return it
    }
    return -1
}

fun filteredListSearch(values: List<Int>): Int {
    values.filter { it > 0 }.forEach {
        if (it > 1) return it
    }
    return -1
}

fun setSearch(values: Set<Int>): Int {
    values.forEach {
        if (it > 1) return it
    }
    return -1
}

fun intArraySearch(values: IntArray): Int {
    values.forEach {
        if (it > 1) return it
    }
    return -1
}

fun indexedSearch(values: List<Int>): Int {
    values.forEachIndexed { _, value ->
        if (value > 1) return value
    }
    return -1
}

fun main() {
    println(listSearch(listOf(1, 2, 3)))
    println(filteredListSearch(listOf(1, 2, 3)))
    println(setSearch(setOf(1, 2, 3)))
    println(intArraySearch(intArrayOf(1, 2, 3)))
    println(indexedSearch(listOf(1, 2, 3)))
}
