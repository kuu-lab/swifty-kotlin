fun grade(n: Int) = when (n) { in 90..100 -> "A"; in 80 until 90 -> "B"; !in 0..100 -> "invalid"; else -> "C" }
fun charWhen(c: Char) = when (c) { in 'a'..'z' -> "lower"; in 'A'..'Z' -> "upper"; '0', '1' -> "bit"; else -> "other" }
fun grade2(n: Int): String { return when (n) { in 90..100 -> "A"; else -> "C" } }

var evalCount = 0
fun trackedSubject(): Int { evalCount++; return 5 }

fun main() {
    println(grade(95)); println(grade(85)); println(grade(50)); println(grade(-1))   // A B C invalid
    println(charWhen('q')); println(charWhen('Q')); println(charWhen('1')); println(charWhen('%'))  // lower upper bit other
    println(grade2(99))                                                            // A
    val n = 42
    val s = when (n) { in 0..50 -> "low"; else -> "high" }                          // low
    println(s)
    val x: Any? = 3.0
    println(when (x) { in listOf(3.0, 4.0) -> "listed"; else -> "other" })         // listed

    // Regression: the subject of a `when` with `in`/`!in` branches must be
    // evaluated exactly once, not once per `in`/`!in` branch tested.
    val r = when (trackedSubject()) { in 1..3 -> "a"; !in 0..4 -> "b"; else -> "c" }
    println(r); println(evalCount)   // b, 1
}
