// DIFF_JVM
operator fun <T> T.rangeUntil(end: T): List<T> = listOf(this)

fun main() {
    for (x in 1.0..<2.0) {
        println(x)
    }
    for (x in 1.0f..<2.0f) {
        println(x)
    }
}
