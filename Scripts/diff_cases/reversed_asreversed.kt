fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.reversed())
    println(list.asReversed())
    val mutable = mutableListOf(1, 2, 3)
    val rev = mutable.asReversed()
    println(rev)
    println(listOf<Int>().reversed())
}
