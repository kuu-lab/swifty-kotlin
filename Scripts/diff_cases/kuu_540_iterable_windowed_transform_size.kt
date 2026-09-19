fun f(xs: List<Int>): Int = xs.windowed(2) { it.sum() }.size

fun main() {
    println(f(listOf(1, 2, 3, 4)))
}
