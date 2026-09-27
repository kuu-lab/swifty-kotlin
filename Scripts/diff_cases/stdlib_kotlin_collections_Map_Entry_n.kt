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
private class DoubleEntry(override val key: String, override val value: Double) : Map.Entry<String, Double>
private enum class EntryKind { FIRST }
private class EnumEntry(override val key: String, override val value: EntryKind) : Map.Entry<String, EntryKind>
private enum class Label : Container.Value<String> {
    VALUE;
    override val value: String get() = "enum"
}
private fun <T> readValue(value: Container.Value<T>): T = value.value

private class ThrowingEntry : Map.Entry<String, Int> {
    override val key: String get() = throw IllegalStateException("key")
    override val value: Int get() = throw IllegalStateException("value")
}

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
    val mutable = mutableMapOf("live" to 1)
    val live: Map.Entry<String, Int> = mutable.entries.first()
    mutable["live"] = 2
    println(live.key)
    println(live.value)
    val throwing: Map.Entry<String, Int> = ThrowingEntry()
    try { println(throwing.key) } catch (e: IllegalStateException) { println(e.message) }
    try { println(throwing.value) } catch (e: IllegalStateException) { println(e.message) }
    val concrete: Map.Entry<String, Double> = DoubleEntry("double", 2.5)
    println(concrete.key)
    println(concrete.value)
    val enumEntry: Map.Entry<Any, Any> = EnumEntry("enum", EntryKind.FIRST)
    println(enumEntry.value)
    println(readValue(Label.VALUE))
}
