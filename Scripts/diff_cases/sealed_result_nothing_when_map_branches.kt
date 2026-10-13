// KUU-1896: both branches, reversed order, and an inferred generic result.
sealed interface Result<out T> {
    data class Success<out T>(val value: T) : Result<T>
    object Failure : Result<Nothing>
}

fun <T, R> Result<T>.map(f: (T) -> R): Result<R> = when (this) {
    Result.Failure -> Result.Failure
    is Result.Success -> Result.Success(f(value))
}

fun <T, R> Result<T>.mapReversed(f: (T) -> R): Result<R> = when (this) {
    is Result.Success -> Result.Success(f(value))
    Result.Failure -> Result.Failure
}

fun <T, R> Result<T>.mapInferred(f: (T) -> R) = when (this) {
    Result.Failure -> Result.Failure
    is Result.Success -> Result.Success(f(value))
}

fun main() {
    val failure: Result<Int> = Result.Failure
    println((Result.Success(3).map { it + 1 } as Result.Success).value)
    println(failure.map { println("unexpected"); it + 1 } === Result.Failure)
    println((Result.Success(3).mapReversed { it * 2 } as Result.Success).value)
    println(failure.mapReversed { println("unexpected"); it * 2 } === Result.Failure)
    println((Result.Success(3).mapInferred { it + 5 } as Result.Success).value)
    println(failure.mapInferred { println("unexpected"); it + 5 } === Result.Failure)
    println((Result.Success(3).map { "value=$it" } as Result.Success).value)
}
