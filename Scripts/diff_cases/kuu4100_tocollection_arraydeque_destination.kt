fun main() {
    println(listOf(1, 2).toCollection(ArrayDeque()))
    println(listOf(3, 4).toCollection(ArrayDeque<Int>()))
    println(listOf(5).toCollection(ArrayDeque(4)))
    println(listOf(6, 7).toCollection(mutableListOf()))
    println(listOf(8).toCollection(ArrayList()))
    println(sequenceOf(9, 10).toCollection(ArrayDeque()))
    val named: ArrayDeque<Int> = listOf(11, 12).toCollection(ArrayDeque())
    println(named)
}
