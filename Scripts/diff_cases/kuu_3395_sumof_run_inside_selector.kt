// KUU-3395: resolve a scope-function call inside an explicit sumOf selector lambda.
fun main() {
    val values = listOf(1, 2)
    println(values.sumOf { x -> run { x } })
}
