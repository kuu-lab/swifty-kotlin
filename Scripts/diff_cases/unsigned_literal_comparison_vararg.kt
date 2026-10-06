// KUU-1331: Unsigned literals must select the UInt comparison vararg overload.
fun main() {
    println(maxOf(1u, 2u, 3u, 4u))
    println(minOf(1u, 2u, 3u, 4u))
}
