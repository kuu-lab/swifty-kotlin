class UserIterator(private val values: List<Int>) : Iterator<Int> {
    private var index = 0
    override fun hasNext(): Boolean = index < values.size
    override fun next(): Int {
        val value = values[index]
        index += 1
        return value
    }
}

fun topLevelSequenceFactories(
    values: Iterable<Int>,
    seed: Int?,
    next: () -> Int?,
    seedFunction: () -> Int?,
    nextFunction: (Int) -> Int?,
): Sequence<Int> {
    val fromIterator = Sequence { UserIterator(listOf(1, 2)) }
    val empty = sequenceOf<Int>()
    val single = sequenceOf(42)
    val generated = generateSequence(seed, nextFunction)
    val generatedSeedFn = generateSequence(seedFunction, nextFunction)
    val generatedNext = generateSequence(next)
    val built = sequence {
        yield(1)
        yieldAll(values)
        yieldAll(fromIterator)
    }
    val iter = iterator {
        yield(2)
        yieldAll(single)
    }
    return built + empty + single + generated + generatedSeedFn + generatedNext + iter.asSequence()
}
