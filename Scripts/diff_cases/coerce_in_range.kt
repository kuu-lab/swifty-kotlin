fun main() {
    // Int.coerceIn(IntRange)
    println(5.coerceIn(1..10))
    println(0.coerceIn(1..10))
    println(15.coerceIn(1..10))

    // Long.coerceIn(LongRange)
    println(5L.coerceIn(1L..10L))
    println(0L.coerceIn(1L..10L))
    println(15L.coerceIn(1L..10L))

    // Precomputed range value
    val r = 1..10
    println(5.coerceIn(r))
    println(0.coerceIn(r))

    val rL = 1L..10L
    println(5L.coerceIn(rL))
    println(0L.coerceIn(rL))

    // Nullable receiver safe-call
    val x: Int? = 5
    val y: Int? = null
    println(x?.coerceIn(1..10))
    println(y?.coerceIn(1..10))
}
