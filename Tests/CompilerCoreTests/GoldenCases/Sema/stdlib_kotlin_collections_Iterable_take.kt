import kotlinx.coroutines.flow.Flow

fun probe(
    iterable: Iterable<Int>,
    list: List<Int>,
    sequence: Sequence<Int>,
    range: IntRange,
    text: String,
    flow: Flow<Int>
) {
    iterable.take(2)
    iterable.takeWhile { it > 0 }
    list.take(2)
    list.takeWhile { it > 0 }
    sequence.take(2)
    sequence.takeWhile { it > 0 }
    range.take(2)
    text.take(2)
    text.takeWhile { it > 'a' }
    flow.take(2)
}
