fun main() {
    println(listOf(1, 3, 4, 6).indexOfFirst { it % 2 == 0 })
    println(listOf(1, 3, 5).indexOfFirst { it % 2 == 0 })
}
