// SKIP-DIFF (DEBT-DIFF-001): KSwiftK's bundled stateIn/shareIn signatures intentionally differ from JVM kotlinx.coroutines, so kotlinc cannot be an oracle.

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

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
}
