// KUU-1896: preserve the independently measured minimal reproducer.
sealed interface Result<out T> {data class Success<out T>(val value:T):Result<T>;object Failure:Result<Nothing>}
fun <T,R> Result<T>.map(f:(T)->R):Result<R> = when(this){Result.Failure->Result.Failure;is Result.Success->Result.Success(f(value))}
fun main(){println((Result.Success(3).map { it+1 } as Result.Success).value)}
