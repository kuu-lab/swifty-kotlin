// KUU-1032: internal kotlinx.io helpers must not shadow public default imports.
import kotlinx.io.*

val x = minOf(5L, 3L)

fun main() {
    println(x)
    println(minOf(5, 3))
    println(minOf(Long.MAX_VALUE, 3L))
    println(minOf(-5L, -3L))
}
