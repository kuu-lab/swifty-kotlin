fun main() {
    println(LongProgression.fromClosedRange(2L, 11L, 3L).toList())
    println(LongProgression.fromClosedRange(2L, 11L, 3).toList())
    println(LongProgression.fromClosedRange(10L, 0L, -3L).toList())
    println(LongProgression.fromClosedRange(0L, Long.MAX_VALUE, Long.MAX_VALUE).toList())
    println(LongProgression.fromClosedRange(Long.MAX_VALUE - 4, Long.MAX_VALUE, 2L).toList())
    println(LongProgression.fromClosedRange(Long.MIN_VALUE + 4, Long.MIN_VALUE, -2L).toList())
    try {
        LongProgression.fromClosedRange(1L, 5L, 0L)
    } catch (e: IllegalArgumentException) {
        println("zero=${e.message}")
    }
    try {
        LongProgression.fromClosedRange(1L, 5L, Long.MIN_VALUE)
    } catch (e: IllegalArgumentException) {
        println("min=${e.message}")
    }
}
