import kotlinx.coroutines.flow.*

fun filters(source: Flow<Int?>, mixed: Flow<Any>): Flow<String> {
    mixed.filterIsInstance<String>()
    return source.filterNotNull().filterNot { it < 0 }
        .drop(1).dropWhile { it < 2 }.takeWhile { it < 10 }
        .mapNotNull { if (it > 0) it.toString() else null }
}

fun lifecycle(source: Flow<Int>): Flow<Int> = source
    .onEach { println(it) }
    .onStart { emit(0) }
    .onCompletion { cause -> if (cause == null) emit(9) }
    .catch { cause -> println(cause.message); emit(-1) }
    .retry(2) { it is IllegalStateException }
    .retryWhen { cause, attempt -> println(cause.message); attempt < 1L }

fun transforms(source: Flow<Int>): Flow<IndexedValue<Int>> {
    source.transform<Int, Int> { emit(it) }
    source.transformWhile<Int, Int> { emit(it); it < 5 }
    source.transformLatest<Int, Int> { emit(it) }
    return source.withIndex()
}

suspend fun indexed(source: Flow<Int>) {
    source.collectIndexed { index, value -> println(index + value) }
}

fun subscription(source: SharedFlow<Int>): SharedFlow<Int> = source.onSubscription { emit(0) }
