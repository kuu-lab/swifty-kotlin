import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

fun <T> publish(flow: MutableSharedFlow<T>, value: T): Boolean = flow.tryEmit(value)

fun main() = runBlocking {
    val state = MutableStateFlow(0)
    println(state.compareAndSet(0, 9))
    println(state.compareAndSet(0, 99))
    state.update { it + 1 }
    val stateView: StateFlow<Int> = state.asStateFlow()
    println(stateView.value)

    val mutableShared: MutableSharedFlow<Int> = state
    println(publish(mutableShared, 11))
    mutableShared.emit(12)
    val sharedStateView: SharedFlow<Int> = mutableShared.asSharedFlow()
    println(stateView.value)
    println(sharedStateView.replayCache)
    println(mutableShared.subscriptionCount.value)
    println(state.subscriptionCount === mutableShared.subscriptionCount)
    println(state.asSharedFlow().replayCache)
    val erased: Any = state
    println(erased is MutableSharedFlow<*>)
    println(publish(erased as MutableSharedFlow<Int>, 13))
    println(stateView.value)
    try {
        mutableShared.resetReplayCache()
    } catch (e: UnsupportedOperationException) {
        println("state reset unsupported")
    }

    val shared = MutableSharedFlow<Int>(replay = 1)
    val sharedView: SharedFlow<Int> = shared.asSharedFlow()
    println(shared.subscriptionCount.value)
    println(publish(shared, 20))
    shared.emit(21)
    println(sharedView.replayCache)
    shared.resetReplayCache()
    println(sharedView.replayCache)
    println(stateView is MutableStateFlow<*>)
    println(sharedView is MutableSharedFlow<*>)

    val nullable = MutableStateFlow<String?>(null)
    val nullableShared: MutableSharedFlow<String?> = nullable
    publish(nullableShared, "ready")
    nullableShared.emit(null)
    println(nullable.value)
}
