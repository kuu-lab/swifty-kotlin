// KUU-1325: seeded callbacks receive the previous value and null ends traversal.
fun nextValue(value: Int): Int? = if (value < 8) value * 2 else null

fun main() {
    println(generateSequence(0) { it + 1 }.take(3).toList())
    val iterator = generateSequence(1) { it + 1 }.iterator()
    println(iterator.next())
    println(iterator.next())
    println(generateSequence(5) { null }.firstOrNull())
    println(generateSequence(5) { null }.toList())
    println(generateSequence(1) { if (it < 8) it * 2 else null }.toList())
    println(generateSequence(1, ::nextValue).toList())
    val step = 2
    val limit = 7
    val captured = generateSequence(1) { if (it < limit) it + step else null }
    println(captured.toList())
    println(captured.toList())
    println(generateSequence { 42 }.take(2).toList())
}
