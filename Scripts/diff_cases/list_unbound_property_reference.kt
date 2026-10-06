fun main() {
    val size = List<Int>::size
    println(size.get(listOf(1, 2)))
    println(size.get(emptyList<Int>()))
    val mutableSize = MutableList<Int>::size
    println(mutableSize.get(mutableListOf(1, 2, 3)))
}
