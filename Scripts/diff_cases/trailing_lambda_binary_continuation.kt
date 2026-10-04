fun sumPlusOne(): Int = listOf(1, 2).fold(0) { acc, x -> acc + x } + 1

fun main() {
    println(sumPlusOne())
}
