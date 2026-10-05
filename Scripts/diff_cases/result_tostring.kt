// Result.toString renders Success(value) / Failure(throwable) on every
// rendering path (println, string template, collection element, toString()).
fun booleanValue(): Boolean = true

fun catchBoolean(block: () -> Boolean): Result<Boolean> = runCatching(block)

fun main() {
    println(Result.success(5))
    println(Result.failure<Int>(IllegalStateException("x")))
    println(runCatching { 42 })
    println(runCatching { 1 / 0 })
    println(runCatching { error("bad") })
    println(runCatching { "s" })
    println(runCatching { null })
    println(listOf(runCatching { 1 }))
    println("x=${runCatching { 1 }}")
    println(runCatching { 1 }.toString())

    println(Result.success(true))
    println(Result.success(false))
    println(runCatching { true })
    println(runCatching { false })
    println(runCatching { 'A' })
    println(runCatching { 1.5f })
    println(runCatching { 1.5 })
    println(runCatching { Unit })
    println(Result.success('A'))
    println(Result.success(1.5f))
    println(Result.success(1.5))
    println(Result.success(Unit))
    println(Result.success<Boolean?>(null))
    println(Result.success<Boolean?>(true))
    println(Result.success(Result.success(true)))

    val result = runCatching { true }
    println(result.toString())
    println("result=$result")
    println(listOf(result, Result.success(false)))
    val erased: Any = result
    println(erased)
    println(erased.toString())

    println(runCatching(::booleanValue))
    val block: () -> Boolean = { true }
    println(runCatching(block))
    println(catchBoolean(block))
    println(catchBoolean { error("callback failed") })
    val first = true
    val second = false
    println(runCatching { first })
    println(runCatching { first && !second })
    val capturing: () -> Boolean = { first && !second }
    println(catchBoolean(capturing))

    println(runCatching { true }.getOrThrow())
    println(runCatching { 'A' }.getOrThrow())
    println(runCatching { 1.5 }.getOrThrow())
    println(runCatching { Unit }.getOrThrow())
}
