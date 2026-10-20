fun main() {
    println(LongProgression.fromClosedRange(2L, 11L, 3L).toList())
    println(LongProgression.fromClosedRange(10L, 0L, -3L).toList())
    println(LongProgression.fromClosedRange(0L, Long.MAX_VALUE, Long.MAX_VALUE).toList())
}
