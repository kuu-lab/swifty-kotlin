private class EntryValue<out K, out V>(
    override val key: K,
    override val value: V
) : Map.Entry<K, V>

private interface Container {
    interface Value<out T> {
        val value: T
        fun read(): T = value
    }
}

private class TextValue(override val value: String) : Container.Value<String>

private fun show(entry: Map.Entry<String, Int>) {
    println(entry.key)
    println(entry.value)
}

fun main() {
    show(EntryValue("source", 7))
    show(mapOf("runtime" to 9).entries.first())
    val wide: Map.Entry<Any, Any> = EntryValue("covariant", 11)
    println(wide.key)
    println(wide.value)
    val nullable: Map.Entry<String?, Int?> = EntryValue(null, null)
    println(nullable.key)
    println(nullable.value)
    val nested: Container.Value<String> = TextValue("nested")
    println(nested.read())
}
