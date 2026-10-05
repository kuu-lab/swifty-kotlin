fun <T> fallback(result: Result<T>, defaultValue: T): T = result.getOrDefault(defaultValue)

fun main() {
    val failed = runCatching { throw IllegalStateException("x") }
    val success = runCatching { 42 }
    println(failed.getOrDefault(-2))
    println(success.getOrDefault(-2))
    println(failed.getOrDefault("fallback"))
    println(failed.getOrDefault(false))
    println(failed.getOrDefault(1234567890123L))
    println(failed.getOrDefault(2.5))
    println(failed.getOrDefault(null))

    val typedFailure = runCatching<Int> { throw IllegalStateException("typed") }
    println(typedFailure.getOrDefault(-3))
    println(fallback(typedFailure, -4))
    println(fallback(success, -4))

    val nullSuccess = runCatching { null }
    println(nullSuccess.getOrDefault(-5))
    println(runCatching<String?> { null }.getOrDefault("not-null"))
    println(runCatching<String?> { throw IllegalStateException("nullable") }.getOrDefault("nullable-default"))
    println(success.getOrDefault(null))

    val absent: Result<Nothing>? = null
    val present: Result<Nothing>? = failed
    println(absent?.getOrDefault(-6))
    println(present?.getOrDefault(-6))

    val wideDefault: Any = "wide-default"
    println(typedFailure.getOrDefault(wideDefault))
    println(success.getOrDefault(wideDefault))

    var evaluations = 0
    fun defaultValue(): Int {
        evaluations += 1
        return -7
    }
    println(failed.getOrDefault(defaultValue()))
    println(success.getOrDefault(defaultValue()))
    println(evaluations)
    println(failed.isFailure)
    println(failed.exceptionOrNull()?.message)
}
