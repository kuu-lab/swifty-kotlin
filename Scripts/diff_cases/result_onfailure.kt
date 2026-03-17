fun main() {
    val success = Result.success(42)
    val failure = Result.failure<Int>(RuntimeException("error"))
    success.onFailure { println("should not print") }
    success.onSuccess { println("success: $it") }
    failure.onFailure { println("failure: ${it.message}") }
    failure.onSuccess { println("should not print") }
    println(success.getOrNull())
    println(failure.getOrNull())
    println(success.getOrDefault(0))
    println(failure.getOrDefault(0))
}
