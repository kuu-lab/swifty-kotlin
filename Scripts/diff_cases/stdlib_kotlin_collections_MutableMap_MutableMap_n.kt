class InputEntry(override val key: String, override val value: Int) : Map.Entry<String, Int>

class InputMap : AbstractMap<String, Int>() {
    override val entries: Set<Map.Entry<String, Int>>
        get() = setOf(InputEntry("source", 9), InputEntry("initial", 2))
}

class CustomMutableMap : AbstractMutableMap<String, Int>() {
    private val backing = mutableMapOf("initial" to 1)
    override val entries: MutableSet<MutableMap.MutableEntry<String, Int>> get() = backing.entries
    override val keys: MutableSet<String> get() = backing.keys
    override val values: MutableCollection<Int> get() = backing.values
    override fun put(key: String, value: Int): Int? {
        println("custom put")
        return backing.put(key, value)
    }
    override fun putAll(from: Map<out String, Int>) {
        println("custom putAll")
        super.putAll(from)
    }
    override fun remove(key: String): Int? {
        println("custom remove")
        return backing.remove(key)
    }
    override fun clear() {
        println("custom clear")
        backing.clear()
    }
}

private fun exercise(target: MutableMap<String, Int>) {
    val keys: MutableSet<String> = target.keys
    val values: MutableCollection<Int> = target.values
    val entries: MutableSet<MutableMap.MutableEntry<String, Int>> = target.entries
    println(target.put("initial", 3))
    println(target.put("new", 4))
    val input: Map<String, Int> = InputMap()
    target.putAll(from = input)
    println(target["source"])
    println(target["initial"])
    println(entries.size)
    println(keys.contains("source"))
    println(values.contains(9))
    println(keys.remove("new"))
    println(target.containsKey("new"))
    println(values.remove(9))
    println(target.containsKey("source"))
    println(target.remove("initial"))
    println(target.remove("missing"))
    target.put("last", 7)
    target.clear()
    println(keys.isEmpty())
    println(values.isEmpty())
    println(target.isEmpty())
}

fun main() {
    exercise(mutableMapOf("initial" to 1))
    exercise(CustomMutableMap())
    val nullable: MutableMap<String?, Int?> = mutableMapOf(null to null)
    println(nullable.put(null, 5))
    println(nullable.put(null, 6))
    println(nullable.remove(null))
    val projected: MutableMap<Any, Int> = mutableMapOf()
    projected.putAll(InputMap())
    println(projected["source"])
}
