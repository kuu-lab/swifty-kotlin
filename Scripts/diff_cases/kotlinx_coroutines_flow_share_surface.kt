import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

class PrintingFlowCollector : FlowCollector<Int> {
    override suspend fun emit(value: Int) {
        println("collector=$value")
    }
}

@Suppress("OPT_IN_USAGE", "OPT_IN_USAGE_ERROR")
fun main() = runBlocking {
    flowOf(1, 2).collect(PrintingFlowCollector())
    val state: StateFlow<Int> = MutableStateFlow(7)
    val shared: SharedFlow<Int> = state
    val widened: Flow<Int> = shared
    println(widened.first())
    println(shared.onSubscription { emit(-1) }
        .onSubscription { emit(-2) }.take(3).toList())
    println(SharingStarted.Eagerly.command(MutableStateFlow(0)).first() == SharingCommand.START)
    println(SharingStarted.Lazily.command(MutableStateFlow(1)).first() == SharingCommand.START)
    println(SharingStarted.WhileSubscribed().command(MutableStateFlow(1)).first() == SharingCommand.START)
    val scope = CoroutineScope(Job())
    val lazyState = flowOf(2, 3).stateIn(scope, SharingStarted.Lazily, -1)
    println(lazyState.value)
    val lazyShared = flowOf(4, 5).shareIn(scope, SharingStarted.Lazily, 2)
    println(lazyShared.replayCache)
    println(flowOf(6).shareIn(scope, SharingStarted.Lazily).replayCache)
    try {
        SharingStarted.WhileSubscribed(-1L)
    } catch (failure: IllegalArgumentException) {
        println("invalid-stop")
    }
    try {
        SharingStarted.WhileSubscribed(0L, -1L)
    } catch (failure: IllegalArgumentException) {
        println("invalid-replay")
    }
    scope.cancel()
}
