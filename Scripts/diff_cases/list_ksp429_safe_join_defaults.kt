// Minimal regression for source-backed joinToString defaults through a safe call.
fun main() {
    val values: List<String>? = listOf("one", "two")
    println(values?.joinToString(","))
    println(values?.joinToString(prefix = "<", postfix = ">"))
}
