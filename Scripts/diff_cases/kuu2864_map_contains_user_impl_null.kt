// KUU-2864: erased Map calls must dispatch through special-builtin barriers.
private object EmptyStringMap : Map<String, Nothing> {
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true
    override fun containsKey(key: String): Boolean = false
    override fun containsValue(value: Nothing): Boolean = false
    override fun get(key: String): Nothing? = null
    override val entries: Set<Map.Entry<String, Nothing>> get() = null!!
    override val keys: Set<String> get() = null!!
    override val values: Collection<Nothing> get() = null!!
}

fun box(): String {
    val map = EmptyStringMap as Map<Any?, Any?>
    if (map.get(null) != null) return "failed get(null)"
    if (map.containsKey(null)) return "failed containsKey(null)"
    if (map.containsValue(null)) return "failed containsValue(null)"
    return "OK"
}

fun main() {
    println(box())
}
