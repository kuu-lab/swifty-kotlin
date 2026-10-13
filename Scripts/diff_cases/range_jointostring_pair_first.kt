// KUU-1871: keep the captured Pair.first transform and flatMap result shape.
class Solver {
    fun join(input: Pair<String, List<Int>>): Pair<String, List<Int>> = (0..4).joinToString("?") { input.first } to (0..4).flatMap { input.second }
}

fun main() {
    println(Solver().join("abc" to listOf(1, 2)))
}
