import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// KSP-675: MutableSharedFlow / SharedFlow are Kotlin source; the replay buffer
// and its eviction are plain Kotlin state transitions. This case pins the
// replay capacity, eviction order, tryEmit/emit results and the interface-typed
// `replayCache` read (SharedFlow<Int> view of a MutableSharedFlow<Int>).

fun main() = runBlocking {
    val shared = MutableSharedFlow<Int>(2)
    println(shared.replayCache)
    println(shared.tryEmit(1))
    shared.emit(2)
    shared.emit(3)
    println(shared.replayCache)

    val view: SharedFlow<Int> = shared
    println(view.replayCache)

    val noReplay = MutableSharedFlow<Int>(0)
    println(noReplay.tryEmit(9))
    noReplay.emit(10)
    println(noReplay.replayCache)
}
