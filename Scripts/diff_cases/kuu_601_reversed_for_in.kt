// KUU-601: A reversed IntProgression must remain iterable in a for-loop.
fun main() {
    for (i in (1..3).reversed()) print(i)
    println()

    val progression = (1..3).reversed()
    for (i in progression) print(i)
    println()

    val range: IntRange = 1..3
    for (i in range.reversed()) print(i)
    println()

    for (i in 3 downTo 1) print(i)
    println()

    println((1..3).reversed().count())
}
