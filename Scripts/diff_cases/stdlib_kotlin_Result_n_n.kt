fun main() {
    val result: Result<String> = runCatching { "value" }
    println(result.isSuccess)
}
