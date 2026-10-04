class CustomEntry(override val key: String, initial: Int) : MutableMap.MutableEntry<String, Int> {
    override val value: Int get() = stored
    private var stored: Int = initial
    override fun setValue(newValue: Int): Int {
        val old = stored
        stored = newValue
        return old
    }
}

class GenericEntry<K, V>(override val key: K, initial: V) : MutableMap.MutableEntry<K, V> {
    override val value: V get() = stored
    private var stored: V = initial
    override fun setValue(newValue: V): V {
        val old = stored
        stored = newValue
        return old
    }
}

private fun <K, V> replace(entry: MutableMap.MutableEntry<K, V>, value: V): V = entry.setValue(value)

fun main() {
    val entry: MutableMap.MutableEntry<String, Int> = CustomEntry("custom", 1)
    println(entry.key)
    println(entry.value)
    println(entry.setValue(4))
    println(entry.value)
    println(replace(entry, 9))
    println(entry.value)
    val concrete = CustomEntry("concrete", 2)
    println(concrete.setValue(5))
    println(concrete.value)
    val nullable: MutableMap.MutableEntry<String?, String?> = GenericEntry(null, "before")
    println(nullable.key)
    println(replace(nullable, null))
    println(nullable.value)
    println(nullable.setValue("after"))
    println(nullable.value)
    val map = mutableMapOf("runtime" to 3)
    val runtime: MutableMap.MutableEntry<String, Int> = map.entries.iterator().next()
    println(replace(runtime, 8))
    println(runtime.value)
    println(map["runtime"])
    val readonly: Map.Entry<String, Int> = runtime
    println(readonly.key)
    println(readonly.value)
}
