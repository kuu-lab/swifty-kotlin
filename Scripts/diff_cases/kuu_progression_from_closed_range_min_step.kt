fun main() {
    try { println(IntProgression.fromClosedRange(10, 0, Int.MIN_VALUE).toList()) } catch (e: IllegalArgumentException) { println("IAE: ${e.message}") }
}
