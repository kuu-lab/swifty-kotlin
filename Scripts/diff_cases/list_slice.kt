fun main() {
    val list = listOf(0, 1, 2, 3, 4, 5)
    println(list.slice(1..3))   // [1, 2, 3]
    println(list.slice(0..0))   // [0]
    println(list.slice(2..5))   // [2, 3, 4, 5]
    println(list.slice(listOf(0, 2, 4)))  // [0, 2, 4]
}
