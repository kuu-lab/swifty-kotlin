import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.*

data class Box(val number: Int)

fun main() {
    val state = MutableStateFlow(10)
    val view = state.asStateFlow()
    println(state.compareAndSet(9, 20))
    println(state.compareAndSet(10, 20))
    state.update { it + 2 }
    println(state.getAndUpdate { it * 2 })
    println(state.updateAndGet { it + 1 })
    state.value = 50
    println(view.value)
    println(view.replayCache)
    println(state.subscriptionCount.value)
    println(view is MutableStateFlow<*>)

    var attempts = 0
    state.update { previous ->
        attempts += 1
        if (attempts == 1) state.value = 60
        previous + 1
    }
    println(attempts)
    println(state.value)

    val original = Box(1)
    val boxes = MutableStateFlow(original)
    println(boxes.compareAndSet(Box(1), Box(1)))
    println(boxes.value === original)
    boxes.value = Box(1)
    println(boxes.value === original)

    val nullable = MutableStateFlow<String?>(null)
    println(nullable.compareAndSet(null, "ready"))
    println(nullable.getAndUpdate { null })
    println(nullable.value)
    try {
        state.resetReplayCache()
    } catch (e: UnsupportedOperationException) {
        println("state reset unsupported")
    }

    val shared = MutableSharedFlow<Int>(2, 3, BufferOverflow.DROP_LATEST)
    val sharedView = shared.asSharedFlow()
    println(shared.tryEmit(1))
    shared.tryEmit(2)
    shared.tryEmit(3)
    val snapshot = sharedView.replayCache
    println(snapshot)
    println(shared.subscriptionCount.value)
    println(sharedView is MutableSharedFlow<*>)
    shared.resetReplayCache()
    println(sharedView.replayCache)
    println(snapshot)

    val unbuffered = MutableSharedFlow<Int>()
    println(unbuffered.tryEmit(4))
    println(unbuffered.replayCache)
    val extra = MutableSharedFlow<Int>(extraBufferCapacity = 2, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    println(extra.tryEmit(5))
    println(extra.replayCache)

    try {
        MutableSharedFlow<Int>(-1)
    } catch (e: IllegalArgumentException) {
        println("negative replay")
    }
    try {
        MutableSharedFlow<Int>(extraBufferCapacity = -1)
    } catch (e: IllegalArgumentException) {
        println("negative extra capacity")
    }
    try {
        MutableSharedFlow<Int>(onBufferOverflow = BufferOverflow.DROP_LATEST)
    } catch (e: IllegalArgumentException) {
        println("overflow without capacity")
    }
}
