import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.coroutines.cancellation.CancellationException

fun main() {
        runBlocking {
        println(flow<Int> { emit(1); throw IllegalStateException("upstream") }
            .onCompletion { cause -> println(cause != null) }
            .catch { cause -> println(cause.message); emit(9) }.toList())
        try {
            flowOf(1).catch { println("must not catch downstream") }
                .onCompletion { cause -> println("downstream:${cause != null}") }
                .collect { throw IllegalArgumentException("downstream") }
        } catch (e: IllegalArgumentException) {
            println(e.message)
        }
        try {
            flow<Int> { throw CancellationException("cancel") }
                .catch { println("manual cancellation") }.toList()
        } catch (e: CancellationException) {
            println(e.message)
        }
        var runs = 0
        println(flow<Int> { runs += 1; emit(runs); if (runs < 3) throw IllegalStateException("retry") }
            .retry(2) { println(it.message); true }.toList())
        println(runs)
        runs = 0
        println(flow<Int> { runs += 1; if (runs < 3) throw IllegalStateException("again"); emit(5) }
            .retryWhen { cause, attempt -> println("${cause.message}:$attempt"); emit(10); attempt < 2L }.toList())
        try {
            flow<Int> { throw IllegalStateException("no retry") }.retry(0).toList()
        } catch (e: IllegalArgumentException) {
            println("zero retry")
        }
        try {
            flowOf(1).retry(-1)
        } catch (e: IllegalArgumentException) {
            println("negative retry")
        }
        println(flow<Int> { throw IllegalStateException("original") }
            .onCompletion { emit(99) }
            .catch { println(it.message); emit(4) }.toList())
        println(flow<Int> { throw IllegalStateException("original") }
            .onCompletion { throw IllegalArgumentException("completion") }
            .catch { cause ->
                println(cause.message)
                for (suppressed in cause.suppressedExceptions) println(suppressed.message)
            }.toList())
        try {
            flowOf(1).retryWhen { _, _ -> println("must not retry downstream"); true }
                .collect { throw IllegalArgumentException("retry downstream") }
        } catch (e: IllegalArgumentException) {
            println(e.message)
        }
        try {
            flow<Int> { throw IllegalStateException("declined") }
                .retry(2) { println("decline"); false }.toList()
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
}
