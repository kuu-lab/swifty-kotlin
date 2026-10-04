import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // catch: handle upstream exception, suppress it
    flow<Int> {
        emit(1)
    }.catch { _: Throwable -> println(-1) }
        .collect { value: Int -> println(value) }

    // retry: retry on failure (no failure here, so retries are not exercised)
    val retried = flow<Int> {
        emit(10)
        emit(20)
    }.retry(1)
    println(retried.toList())

    // retryWhen: conditional retry with attempt count
    val retriedWhen = flow<Int> {
        emit(7)
    }.retryWhen { _: Throwable, attempt: Long ->
        attempt < 1L
    }
    println(retriedWhen.toList())

    // onErrorReturn semantics: emit fallback value on error
    val withFallback = try {
        flow<Int> {
            emit(42)
        }.toList()
    } catch (e: Throwable) {
        listOf(99)
    }
    println(withFallback)

    // onErrorResume semantics: switch to fallback flow on error
    val fallback = flowOf(100, 200)
    val withResume = try {
        flow<Int> {
            emit(5)
        }.toList()
    } catch (e: Throwable) {
        fallback.toList()
    }
    println(withResume)

    // onCompletion: run side-effect after the upstream flow completes
    val completed = flow<Int> {
        emit(3)
        emit(6)
    }.onCompletion { cause: Throwable? ->
        if (cause == null) println("done") else println("error")
    }.toList()
    println(completed)
}
