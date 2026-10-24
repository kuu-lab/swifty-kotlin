// CANDIDATE-ONLY: KSwiftK's bundled stateIn/shareIn signatures intentionally differ from JVM kotlinx.coroutines.

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlin.coroutines.EmptyCoroutineContext

fun main() = runBlocking {
    val state = MutableStateFlow(10)
    println(state.value)

    state.tryEmit(20)
    println(state.value)

    state.emit(30)
    println(state.value)

    val view: StateFlow<Int> = state
    println(view.value)
    println(view.replayCache)

    val initial = 0
    val stateFromFlow = flowOf(1, 2, 3).stateIn(initial)
    println(stateFromFlow.value)

    val shared = flowOf(4, 5, 6).shareIn(1)
    println(shared.replayCache)

    // KSwiftK currently preserves identity for SharedFlow fused operators, including configurable buffer and conflate.
    val mutableShared = MutableSharedFlow<Int>(1)
    val sharedView = mutableShared.asSharedFlow()
    println(sharedView.buffer(0) === sharedView)
    println(sharedView.buffer(2) === sharedView)
    println(sharedView.buffer(2, BufferOverflow.DROP_OLDEST) === sharedView)
    println(sharedView.flowOn(EmptyCoroutineContext) === sharedView)
    println(sharedView.cancellable() === sharedView)
    println(sharedView.conflate() === sharedView)
    println(view.distinctUntilChanged() === view)
}
