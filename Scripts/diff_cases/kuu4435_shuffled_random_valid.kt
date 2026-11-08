// shuffled(random:) with admissible arguments keeps working on every
// collection receiver shape (KUU-4435). Sorted output keeps the comparison
// deterministic; sizes cover the no-arg and range-receiver paths.
import kotlin.random.Random

fun List<Int>.shuffled(seed: Int): String = "user-$seed"

fun main() {
    println(listOf(3, 1, 2).shuffled(Random(42)).sorted())
    println(listOf(1, 2, 3).shuffled().size)
    println(listOf(1, 2, 3).shuffled(Random.Default).sorted())
    println(sequenceOf(4, 5, 6).shuffled(Random(7)).toList().sorted())
    println(setOf(7, 8).shuffled(Random(9)).sorted())
    println(mutableListOf(9, 8, 7).shuffled(Random(3)).sorted())
    println((1..5).shuffled().size)
    println(listOf(1, 2, 3).shuffled(42))
}
