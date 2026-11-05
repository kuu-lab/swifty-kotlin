// KUU-4167: an unsuffixed integer literal adapts to the wider primitive
// parameter of the selected minOf/maxOf overload, matching kotlinc.
fun main() {
    println(maxOf(1, 2L))
    println(minOf(1, 2L))
    println(maxOf(1L, 2))
    println(minOf(1L, 2))
    println(maxOf(1, 2))
    println(minOf(1, 2))
    println(maxOf(1, 2, 3L))
    println(minOf(1, 2L, 3))
    println(maxOf(-5, 2L))
    println(minOf(-5L, 2))
    val x = 5L
    println(maxOf(1, x))
    println(minOf(x, 2))
    println(maxOf(7, 2, 9L))
    println(maxOf(1, 5000000000))
    println(minOf(1, 5000000000))
    println(maxOf(1, 2, 5000000000))
}
