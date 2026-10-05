import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.*

class IntCollector : FlowCollector<Int> {
    override suspend fun emit(value: Int) {}
}

fun shared(source: Flow<Int>, scope: CoroutineScope): SharedFlow<Int> =
    source.shareIn(scope, SharingStarted.Eagerly, 2).onSubscription { emit(0) }

fun state(source: Flow<Int>, scope: CoroutineScope): StateFlow<Int> =
    source.stateIn(scope, SharingStarted.Lazily, -1)

fun commands(count: StateFlow<Int>): Flow<SharingCommand> =
    SharingStarted.WhileSubscribed(10L, 20L).command(count)

suspend fun collectBoth(state: StateFlow<Int>) {
    val shared: SharedFlow<Int> = state
    val source: Flow<Int> = shared
    source.collect(IntCollector())
    source.collect { println(it) }
    source.shareIn(2)
    source.stateIn(0)
}
