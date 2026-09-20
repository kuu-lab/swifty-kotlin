// KUU-569: Range and progression receivers must inherit the generic Iterable
// extension surface, including parenthesized range expressions.
import kotlin.random.Random

fun main() {
    println((1..5).elementAt(2))
    println((1..5).indexOf(3))
    println((1..5).lastIndexOf(3))
    println((1..5).asIterable().toList())
    println((1..5).asSequence().toList())
    println((1..5).toSet())
    println((1..5).toMutableList())
    println((1..5).joinToString("-"))
    println((1..5).maxOrNull())
    println((1..5).sumOf { it * 2 })
    println((1..3).zip(listOf(4, 5, 6)))
    println((1..3).zip(listOf(4, 5, 6)) { left, right -> left + right })
    println((1..3).associateWith { it * 10 })
    println((1..5).groupBy { it % 2 })
    println((1..5).partition { it % 2 == 0 })
    println((1..5).takeWhile { it < 4 })
    println((1..5).dropWhile { it < 4 })
    println((1..5).count { it % 2 == 1 })
    println((1..5).distinct())
    println((1..5).sortedDescending())
    println((1..3).flatMap { listOf(it, -it) })
    println((1..3).flatMap { sequenceOf(it, -it) })
    println((1..5).intersect(listOf(2, 4, 6)))
    println((1..3).union(listOf(3, 4)))
    println((1..5).subtract(listOf(2, 4)))
    println((1..3).withIndex().map { "${it.index}:${it.value}" })
    println((1..5).shuffled(Random(7)).sorted())
    println((1..3).mapIndexed { index, value -> index + value })
    println(('a'..'c').joinToString(","))
    println(('a'..'c').joinToString(prefix = "<", postfix = ">"))
    println(('a'..'e').joinToString("-", "<", ">", 3, "..."))

    val progression = 1..10 step 3
    println(progression.elementAt(2))
    println(progression.joinToString(","))
    println(progression.toSet())
    println(progression.withIndex().map { "${it.index}:${it.value}" })
}
