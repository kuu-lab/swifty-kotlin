class Entry(override val key: String, override val value: Int) : Map.Entry<String, Int>

class Input : AbstractMap<String, Int>() {
    override val entries: Set<Map.Entry<String, Int>> get() = setOf(Entry("source", 9))
}

class Target : AbstractMutableMap<String, Int>() {
    private val backing = mutableMapOf("initial" to 1)
    override val entries: MutableSet<MutableMap.MutableEntry<String, Int>> get() = backing.entries
    override fun put(key: String, value: Int): Int? = backing.put(key, value)
}

fun exercise(target: MutableMap<String, Int>) {
    target.put("new", 4)
    val input: Map<String, Int> = Input()
    target.putAll(input)
    println(target["source"])
}

fun main() {
    val target = Target()
    exercise(target)
    println(target.toString())
    val erased: Any = target
    println(erased)
    println(Input().toString())
}
