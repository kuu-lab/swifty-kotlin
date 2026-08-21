@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    val result: Result<String> = runCatching { "value" }
    val constructed: Result<Int> = Result(7)
    println(result.isSuccess)
    println(constructed.isSuccess)
    println(constructed.getOrThrow())
}
