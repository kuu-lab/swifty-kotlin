class IntContainer(private val elements: List<Int>) {
    operator fun get(index: Int): Int = elements[index]
    operator fun contains(element: Int): Boolean = elements.contains(element)

    operator fun iterator(): Iterator<Int> = elements.iterator()
}

class Matrix(private val rows: List<List<Int>>) {
    operator fun get(row: Int, col: Int): Int = rows[row][col]
}

class MutableContainer(private val elements: MutableList<Int>) {
    operator fun get(index: Int): Int = elements[index]
    operator fun set(index: Int, value: Int) { elements[index] = value }
}

fun main() {
    // Index operator: get()
    val container = IntContainer(listOf(10, 20, 30))
    println(container[0])
    println(container[1])
    println(container[2])

    // Multi-index operator: get(row, col)
    val matrix = Matrix(listOf(listOf(1, 2), listOf(3, 4)))
    println(matrix[0, 0])
    println(matrix[0, 1])
    println(matrix[1, 0])
    println(matrix[1, 1])

    // Index operator: set()
    val mutable = MutableContainer(mutableListOf(1, 2, 3))
    mutable[0] = 100
    mutable[2] = 300
    println(mutable[0])
    println(mutable[1])
    println(mutable[2])

    // Containment operator: contains() / in
    println(10 in container)
    println(20 in container)
    println(99 in container)
    println(10 !in container)

    // Iterator operator: for-in loop
    for (item in container) {
        println(item)
    }

    // rangeTo operator on Int (built-in)
    for (i in 1..3) {
        println(i)
    }
}
