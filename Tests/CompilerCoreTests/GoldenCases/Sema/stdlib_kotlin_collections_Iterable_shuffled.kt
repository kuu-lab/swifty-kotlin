import kotlin.random.Random

fun shuffleIterableDefault(values: Iterable<Int>): List<Int> {
    return values.shuffled()
}

fun shuffleIterableWithRandom(values: Iterable<String?>, random: Random): List<String?> {
    return values.shuffled(random)
}
