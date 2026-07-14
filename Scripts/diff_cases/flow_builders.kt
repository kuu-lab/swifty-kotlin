// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    flowOf(1, 2, 3)
        .collect { println(it) }

    emptyFlow<Int>()
        .collect { println(it) }

    listOf(4, 5, 6)
        .asFlow()
        .map { it * 10 }
        .collect { println(it) }

    channelFlow<Int> {
        emit(7)
        emit(8)
    }.collect { println(it) }

    callbackFlow<Int> {
        emit(9)
        emit(10)
    }.collect { println(it) }
}
