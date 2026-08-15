class Score(val value: Int) : Comparable<Score> {
    override fun compareTo(other: Score): Int = value.compareTo(other.value)
}

fun main() {
    println(Score(5).coerceIn(null, Score(3)).value)
    println(Score(5).coerceIn(Score(7), null).value)
    println(Score(5).coerceIn(Score(1), Score(10)).value)
    println(9.9.coerceIn(1.0..10.0))
    println(0.0f.coerceIn(1.0f..10.0f))
}
