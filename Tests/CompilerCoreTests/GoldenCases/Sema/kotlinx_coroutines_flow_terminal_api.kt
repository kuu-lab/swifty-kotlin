import kotlinx.coroutines.flow.*

suspend fun terminalValues(source: Flow<Int>) {
    val first: Int? = source.firstOrNull()
    val matched: Int? = source.firstOrNull { it > 1 }
    val last: Int = source.last()
    val lastNullable: Int? = source.lastOrNull()
    val single: Int? = source.singleOrNull()
    val count: Int = source.count { it > 1 }
    val any: Boolean = source.any { it > 1 }
    val all: Boolean = source.all { it > 1 }
    val none: Boolean = source.none { it > 1 }
    val destination = mutableListOf<Any?>()
    val collection: MutableList<Any?> = source.toCollection(destination)
    val set: Set<Int> = source.toSet()
    val suppliedSet: Set<Int> = source.toSet(mutableSetOf<Int>())
}

fun accumulating(source: Flow<Int>) {
    val scanned: Flow<Int> = source.scan(0) { acc, value -> acc + value }
    val folded: Flow<String> = source.runningFold("") { acc, value -> acc + value }
    val reduced: Flow<Int> = source.runningReduce { acc, value -> acc + value }
    val fallback: Flow<Int> = source.onEmpty { emit(1) }
}

suspend fun collectors(source: Flow<Int>, collector: FlowCollector<Int>) {
    source.collectLatest { value -> println(value) }
    source.collectIndexed { index, value -> println(index + value) }
    collector.emitAll(source)
    val forwarded: Flow<Int> = flow { emitAll(source) }
}
