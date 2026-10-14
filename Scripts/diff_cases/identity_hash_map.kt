// KUU-2060: equal-but-distinct nominal objects must remain distinct keys/values.
import java.util.IdentityHashMap

data class IdentityToken(val id: Int)

class SingletonSourceSet<T>(private val element: T) : AbstractSet<T>() {
    override val size: Int get() = 1
    override fun iterator(): Iterator<T> = listOf(element).iterator()
}

class IdentityEntry(
    override val key: IdentityToken?,
    private var current: IdentityToken?
) : MutableMap.MutableEntry<IdentityToken?, IdentityToken?> {
    override val value: IdentityToken? get() = current
    override fun setValue(newValue: IdentityToken?): IdentityToken? {
        val previous = current
        current = newValue
        return previous
    }
}

fun identityMap(): MutableMap<String, Int> = IdentityHashMap<String, Int>()
fun valueMap(): MutableMap<String, Int> = HashMap<String, Int>()

fun main() {
    val a = IdentityToken(1)
    val b = IdentityToken(1)
    val v = IdentityToken(2)
    val equalV = IdentityToken(2)
    check(a == b && a !== b && v == equalV && v !== equalV)
    val concrete = IdentityHashMap<IdentityToken?, IdentityToken?>()
    val map: MutableMap<IdentityToken?, IdentityToken?> = concrete
    val keys = map.keys
    val values = map.values
    val entries = map.entries
    check(map.put(a, v) == null)
    check(map[b] == null)
    check(map[a] === v)
    check(map.containsKey(a) && !map.containsKey(b))
    check(map.containsValue(v) && !map.containsValue(equalV))
    check(keys.contains(a) && !keys.contains(b))
    check(values.contains(v) && !values.contains(equalV))
    check(!values.remove(equalV) && map.size == 1)
    check(map.put(b, equalV) == null && map.size == 2)
    check(keys.size == 2 && entries.size == 2 && values.size == 2)
    check(map.put(a, equalV) === v && map[a] === equalV)
    check(map.remove(IdentityToken(1)) == null && map.size == 2)
    check(map.remove(b) === equalV && map.size == 1)
    check(map.put(null, null) == null && map.containsKey(null))
    check(map.containsValue(null) && keys.contains(null) && values.contains(null))
    check(map.remove(null) == null && !map.containsKey(null))
    check(values.remove(equalV) && map.isEmpty())
    map[a] = v
    val matching = IdentityHashMap<IdentityToken?, IdentityToken?>()
    matching[a] = v
    val differentValue = IdentityHashMap<IdentityToken?, IdentityToken?>()
    differentValue[a] = equalV
    val differentKey = IdentityHashMap<IdentityToken?, IdentityToken?>()
    differentKey[b] = v
    check(keys == matching.keys && keys.hashCode() == matching.keys.hashCode())
    check(keys != setOf(b))
    check(keys == SingletonSourceSet(a))
    check(keys != SingletonSourceSet(b))
    check(entries == matching.entries && entries.hashCode() == matching.entries.hashCode())
    check(entries != differentValue.entries && entries != differentKey.entries)
    check(entries.first().hashCode() == concrete.hashCode())
    check(entries.first() == matching.entries.first())
    check(entries.first() != differentValue.entries.first())
    check(entries.first() != differentKey.entries.first())
    val sourceEntry = IdentityEntry(a, v)
    check(entries.first() == sourceEntry)
    check(entries.contains(sourceEntry))
    check(entries == SingletonSourceSet(sourceEntry))
    check(entries != SingletonSourceSet(IdentityEntry(a, equalV)))
    check(!entries.contains(IdentityEntry(a, equalV)))
    check(!entries.contains(IdentityEntry(b, v)))
    check(entries.contains(matching.entries.first()))
    check(!entries.contains(differentValue.entries.first()))
    check(!entries.contains(differentKey.entries.first()))
    check(!entries.remove(differentValue.entries.first()) && map.size == 1)
    check(entries.remove(matching.entries.first()) && map.isEmpty())
    map[a] = v
    val entry = entries.first()
    check(entry.setValue(equalV) === v && map[a] === equalV)
    check(keys.remove(a) && map.isEmpty())
    concrete.putAll(matching)
    check(entries.remove(sourceEntry) && map.isEmpty())
    concrete.putAll(matching)
    check(concrete[a] === v)
    val copied = IdentityHashMap<IdentityToken?, IdentityToken?>(concrete)
    check(copied[a] === v && copied[b] == null)
    check(copied == concrete && copied.hashCode() == concrete.hashCode())
    check(copied != differentKey && copied != differentValue)
    check(!values.containsAll(listOf(equalV)))
    check(!keys.containsAll(listOf(b)))
    check(!values.removeAll(differentValue.values) && map.size == 1)
    check(!keys.removeAll(differentKey.keys) && map.size == 1)
    check(!entries.removeAll(differentValue.entries) && map.size == 1)
    check(values.retainAll(differentValue.values) && map.isEmpty())
    map[a] = v
    check(keys.retainAll(differentKey.keys) && map.isEmpty())
    map[a] = v
    check(entries.retainAll(differentValue.entries) && map.isEmpty())
    map[a] = v
    check(keys.removeAll(listOf(b)) && map.isEmpty())
    map[a] = v
    check(values.removeAll(listOf(equalV)) && map.isEmpty())
    map[a] = v
    map.clear()
    check(keys.isEmpty() && values.isEmpty() && entries.isEmpty())
    check(IdentityHashMap<IdentityToken, IdentityToken>(0).isEmpty())
    var rejected = false
    try {
        IdentityHashMap<IdentityToken, IdentityToken>(-1)
    } catch (e: IllegalArgumentException) {
        rejected = true
    }
    check(rejected)
    val ordinary = HashMap<IdentityToken, IdentityToken>()
    ordinary[a] = v
    check(ordinary[b] === v)
    check(ordinary.put(b, equalV) === v && ordinary.size == 1)
    check(ordinary.containsValue(v))
    val ordinaryInterface: Map<IdentityToken, IdentityToken> = ordinary
    check(ordinaryInterface.containsKey(b) && ordinaryInterface.containsValue(v))
    check(ordinary.values.removeAll(listOf(v)) && ordinary.isEmpty())
    println("identity-map: OK")
    println("hash-map control: OK")
}
