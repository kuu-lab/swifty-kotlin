// KUU-1597 Sema owner: pin Sequence flatMapTo/flatMapIndexedTo result types and a custom receiver overload; destination effects stay in Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_flat.kt.
class UserSequence(private val values: Sequence<Int>) : Sequence<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun UserSequence.flatMapTo(
    destination: MutableList<Int>,
    transform: (Int) -> Sequence<Int>,
): MutableList<Int> = destination

fun main() {
    val source: Sequence<Int> = sequenceOf(1, 2, 3)

    val iterableDestination: MutableList<Int> = mutableListOf(99)
    val iterableResult: MutableList<Int> = source.flatMapTo(iterableDestination) { value ->
        listOf(value, value * 10)
    }

    val sequenceDestination: MutableList<Int> = mutableListOf(88)
    val sequenceResult: MutableList<Int> = source.flatMapTo(sequenceDestination) { value ->
        sequenceOf(value, value * 100)
    }

    val numberDestination: MutableList<Number> = mutableListOf(77)
    val numberResult: MutableList<Number> = source.flatMapTo(numberDestination) { value ->
        sequenceOf(value * 2)
    }

    val indexedDestination: MutableList<Int> = mutableListOf(66)
    val indexedResult: MutableList<Int> = source.flatMapIndexedTo(indexedDestination) { index, value ->
        sequenceOf(index, value * 3)
    }

    val userDestination: MutableList<Int> = mutableListOf(44)
    val userResult: MutableList<Int> = UserSequence(sequenceOf(5)).flatMapTo(userDestination) {
        sequenceOf(it * 2)
    }
}
