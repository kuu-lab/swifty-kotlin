// KUU-1165: infer the collector parameter from emissions, without flow<Int>.
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

fun accept(value: Int) { println(value) }
fun acceptString(value: String) { println(value) }
fun acceptNullable(value: Int?) { println(value) }
fun acceptLong(value: Long) { println(value) }
fun <T> identity(value: T): T = value
class Sink { fun emit(value: String) { println(value) } }

suspend fun capturedPredicate(pred: suspend (Int) -> Boolean) {
    flow { emit(1) }.collect { println(pred(it)) }
}

fun main() = runBlocking {
    flow { emit(1) }.collect { value -> accept(value) }
    val result = flow {
        val value = identity(2)
        emit(value)
        if (true) emit(3) else emit(4)
    }
    result.collect { accept(it) }
    flow { flowOf(5, 6).collect { emit(it) } }.collect { accept(it) }
    flow { emitAll(flowOf(7, 8)) }.collect { accept(it) }
    flow {
        val nested = flow { emit("nested") }
        nested.collect { acceptString(it) }
        emit(9)
    }.collect { accept(it) }
    flow { emit(null); emit(10) }.collect { acceptNullable(it) }
    flow { emit("string") }.collect { acceptString(it) }
    flow { with(Sink()) { emit("sink") }; emit(14) }.collect { accept(it) }
    val expected: Flow<Int> = flow { emit(11) }
    expected.collect { accept(it) }
    flow<Long> { emit(12) }.collect { acceptLong(it) }
    val scale = 2
    val operation = { value: Int -> println(value * scale) }
    flow { emit(13) }.collect { operation(it) }
    val threshold = 0
    capturedPredicate { it > threshold }
}
