import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.flow.*
import kotlin.time.Duration

fun operators(source: Flow<Int>, channel: ReceiveChannel<Int>, period: Duration): Flow<Int> {
    val distinct = source.distinctUntilChanged().distinctUntilChangedBy { it % 2 }
    val equivalent = source.distinctUntilChanged { old, new -> old == new }
    val sampled = source.sample(1L).sample(period)
    val mapped = source.mapLatest { it + 1 }
    val transformed = source.transformLatest<Int, Int> { value -> emit(value) }
    val received = channel.receiveAsFlow()
    val consumed = channel.consumeAsFlow()
    val combined = combine(source, distinct, equivalent) { values: Array<Int> -> values[0] }
    val iterable = combine(listOf(source, distinct)) { values: Array<Int> -> values[0] }
    return source.combineLatest(sampled, mapped, transformed, combined) { a, b, c, d, e -> a + b + c + d + e }
}
