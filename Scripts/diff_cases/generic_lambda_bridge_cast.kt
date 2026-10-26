// KUU-3345: pass a non-reified unchecked cast through a generic function value.
private fun <T : Any> invokeIt(any: Any, extract: (T) -> String): String {
    @Suppress("UNCHECKED_CAST")
    return extract(any as T)
}

fun main() {
    println(invokeIt<String>("x") { it + "OK" })
}
