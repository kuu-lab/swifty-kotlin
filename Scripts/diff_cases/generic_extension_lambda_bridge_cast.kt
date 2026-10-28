// KUU-3177: invoking T.() -> R after an unchecked Any as T cast must use the
// lambda's erased bridge so an incompatible receiver fails with ClassCastException.
private interface Bindings {
    val value: String
}

private class StringBindings(override val value: String) : Bindings

private fun <T : Any> invokeExtension(any: Any, extract: T.() -> String): String {
    @Suppress("UNCHECKED_CAST")
    return (any as T).extract()
}

fun main() {
    println(invokeExtension<Bindings>(StringBindings("OK")) { value })
    try {
        invokeExtension<Bindings>("wrong-type") { value }
        println("missing cast failure")
    } catch (_: ClassCastException) {
        println("ClassCastException")
    }
}
