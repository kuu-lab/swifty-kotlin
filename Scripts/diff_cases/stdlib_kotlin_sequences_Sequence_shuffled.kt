import kotlin.random.Random

fun main() {
    val source = sequenceOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)

    val noArg = source.shuffled().toList()
    println(noArg.size)
    println(noArg.sorted() == source.toList().sorted())

    val withRandom = source.shuffled(Random(42)).toList()
    println(withRandom.size)
    println(withRandom.sorted() == source.toList().sorted())

    // Source sequence is untouched by shuffled() (non-destructive, re-iterable).
    println(source.toList())

    println(emptySequence<Int>().shuffled().toList())
    println(sequenceOf(42).shuffled().toList())

    // shuffled() on a Sequence derived from a lazy pipeline (map/filter upstream).
    val piped = sequenceOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10).filter { it % 2 == 0 }.map { it * 10 }
    val pipedShuffled = piped.shuffled(Random(7)).toList()
    println(pipedShuffled.size)
    println(pipedShuffled.sorted() == piped.toList().sorted())
}
