// Result.toString renders Success(value) / Failure(throwable) on every
// rendering path (println, string template, collection element, toString()).
fun main() {
    println(runCatching { 42 })
    println(runCatching { error("bad") })
    println(runCatching { "s" })
    println(runCatching { null })
    println(listOf(runCatching { 1 }))
    println("x=${runCatching { 1 }}")
    println(runCatching { 1 }.toString())
}
