class MyStrMap : HashMap<String, Int>()

open class NamedMap(val name: String) : HashMap<String, Int>() {
    init { put("initial", 1) }
}

class ChildMap : NamedMap("child")

class TrackingMap : HashMap<String, Int>() {
    var writes = 0
    var reads = 0
    override fun put(key: String, value: Int): Int? {
        writes++
        return super.put(key, value)
    }
    override fun get(key: String): Int? {
        reads++
        return super.get(key)
    }
}

class NoStorageMap : HashMap<String, Int>() {
    var writes = 0
    var reads = 0
    override fun put(key: String, value: Int): Int? {
        writes++
        return null
    }
    override fun get(key: String): Int? {
        reads++
        return null
    }
    override val size: Int get() = 123
}

class VisibleEntriesMap : HashMap<String, Int>() {
    override val size: Int get() = 1
    override val entries: MutableSet<MutableMap.MutableEntry<String, Int>>
        get() = hashMapOf("visible" to 11).entries
}

fun putThroughMutableMap(map: MutableMap<String, Int>) {
    map.put("tracked", 9)
}

fun getThroughMap(map: Map<String, Int>): Int? = map["tracked"]

fun sizeThroughMap(map: Map<String, Int>): Int = map.size

fun main() {
    val minimal = MyStrMap()
    minimal["k"] = 5
    println(minimal["k"])

    val mm = ChildMap()
    println(mm.name)
    println(mm["initial"])
    println(mm.put("k", 5))
    println(mm.put("k", 7))
    val map: Map<String, Int> = mm
    val mutable: MutableMap<String, Int> = mm
    println(map["k"])
    mutable["second"] = 2
    println(mm.size)
    println(mm.containsKey("second"))
    println(mm.containsValue(7))
    println(mm.entries.size)
    println(mm.keys.contains("k"))
    println(mm.values.contains(2))
    println(mm.remove("k"))
    println(mm["k"])
    mm.putAll(mapOf("third" to 3))
    println(mm["third"])
    mm.clear()
    println(mm.isEmpty())
    println(mm.size)
    val separate = ChildMap()
    println(separate["initial"])
    val erased: Any = separate
    println(erased is HashMap<*, *>)

    val tracking = TrackingMap()
    putThroughMutableMap(tracking)
    println(tracking.writes)
    println(getThroughMap(tracking))
    println(tracking.reads)

    val noStorage = NoStorageMap()
    putThroughMutableMap(noStorage)
    println(noStorage.writes)
    println(getThroughMap(noStorage))
    println(noStorage.reads)
    println(sizeThroughMap(noStorage))

    val copied = hashMapOf<String, Int>()
    copied.putAll(VisibleEntriesMap())
    println(copied["visible"])
}
