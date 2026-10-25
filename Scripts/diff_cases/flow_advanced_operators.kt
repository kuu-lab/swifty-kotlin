import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val transformed = flow<Int> {
        emit(1)
        emit(2)
        emit(3)
        emit(4)
    }
        .map { it * 10 }
        .takeWhile { it <= 30 }
        .dropWhile { it < 20 }
        .toList()
    println(transformed)

    val concat = flow<Int> {
        emit(1)
        emit(2)
    }.flatMapConcat { value ->
        flow<Int> {
            emit(value)
            emit(value * 10)
        }
    }.toList()
    println(concat)

    val mergedFlat = flow<Int> {
        emit(1)
        emit(2)
    }.flatMapMerge { value ->
        flow<Int> {
            emit(value + 100)
            emit(value + 200)
        }
    }.toList()
    var mergedFlatSum = 0
    for (value in mergedFlat) mergedFlatSum += value
    println("${mergedFlat.size}:$mergedFlatSum")

    val latestFlat = flow<Int> {
        emit(1)
        emit(2)
    }.flatMapLatest { value ->
        flow<Int> {
            emit(value)
            emit(value * 100)
        }
    }.toList()
    println(latestFlat)

    val left = flow<Int> {
        emit(1)
        emit(2)
        emit(3)
    }
    val right = flow<Int> {
        emit(10)
        emit(20)
        emit(30)
    }

    println(left.zip(right) { a, b -> a + b }.toList())
    // Single values keep this case independent of combine's racing snapshots.
    println(flowOf(1).combine(flowOf(10)) { a, b -> a * b }.toList())
    val mergedInputs = merge(left, right).toList()
    var mergedInputsSum = 0
    for (value in mergedInputs) mergedInputsSum += value
    println("${mergedInputs.size}:$mergedInputsSum")

    val buffered = flow<Int> {
        emit(5)
        emit(6)
        emit(7)
    }
        .buffer(2)
        .flowOn(Dispatchers.Default)
        .onEach { delay(1) }
        .toList()
    println(buffered)
}
