import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun update(state: MutableStateFlow<Int>, next: Int) {
    state.value = next
}

fun <T> replace(state: MutableStateFlow<T>, next: T) {
    state.value = next
}

fun main() = runBlocking {
    val state = MutableStateFlow(0)
    val view: StateFlow<Int> = state
    val initialReplay = state.replayCache
    state.value = 5
    println(state.value)
    println(view.value)
    println(state.replayCache)
    println(initialReplay)
    println(state.first())

    update(state, 8)
    state.value += 2
    println(state.value)
    println(state.replayCache)
    state.tryEmit(12)
    state.value = 15
    state.emit(20)
    println(view.value)
    println(state.replayCache)

    val nullable = MutableStateFlow<String?>("initial")
    nullable.value = null
    println(nullable.value)
    println(nullable.replayCache)
    replace(nullable, "updated")
    println(nullable.value)
    println(nullable.replayCache)
    println(nullable.first())

    val wide = MutableStateFlow(0L)
    wide.value = 5000000000L
    println(wide.value)
    println(wide.replayCache)

    val flag = MutableStateFlow(false)
    flag.value = true
    println(flag.value)
    println(flag.replayCache)
}
