fun main() {
    val success: Result<Int> = Result.success(42)
    println(success.isSuccess)
    println(success.getOrNull())

    val failure: Result<String> = Result.failure(IllegalStateException("boom"))
    println(failure.isFailure)
    println(failure.exceptionOrNull()?.message)
}
