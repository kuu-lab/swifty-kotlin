import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.*

fun main() {
    val state = MutableStateFlow(1)
    state.value = 2
    state.compareAndSet(2, 3)
    state.update { it + 1 }
    state.getAndUpdate { it + 1 }
    state.updateAndGet { it + 1 }
    val count: StateFlow<Int> = state.subscriptionCount
    val view: StateFlow<Int> = state.asStateFlow()
    val sharedView: SharedFlow<Int> = state.asSharedFlow()
    view.distinctUntilChanged().conflate().cancellable().flowOn(EmptyCoroutineContext).buffer(0)
    val shared = MutableSharedFlow<Int>(2, 1, BufferOverflow.DROP_OLDEST)
    shared.tryEmit(1)
    shared.resetReplayCache()
    shared.asSharedFlow().buffer()
}
