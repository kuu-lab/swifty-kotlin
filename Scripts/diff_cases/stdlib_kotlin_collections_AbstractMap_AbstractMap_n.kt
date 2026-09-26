// KSP-1032: AbstractMap supplies the read-only Map surface to subclasses that
// only provide `entries`, so exercise it through an AbstractMap-typed receiver.

import kotlin.collections.AbstractMap
import kotlin.collections.Map
import kotlin.collections.Set

class ProbeMap : AbstractMap<String, Int?>() {
    override val entries: Set<Map.Entry<String, Int?>>
        get() = mutableMapOf<String, Int?>(
            "one" to 1,
            "missing" to null,
        ).entries
}

class EmptyMap : AbstractMap<String, Int?>() {
    override val entries: Set<Map.Entry<String, Int?>>
        get() = emptyMap<String, Int?>().entries
}

fun main() {
    val map: AbstractMap<String, Int?> = ProbeMap()
    println(map.size)
    println(map["one"])
    println(map["missing"] == null)
    println(map["absent"] == null)
    println(map.get("one"))
    println(map.containsKey("missing"))
    println(map.containsKey("absent"))
    println(map.containsValue(null))
    println(map.containsValue(2))
    println(map.isEmpty())
    println(map.keys)
    println(map.values)
    println(map == ProbeMap())
    println(map == mapOf<String, Int?>("one" to 1, "missing" to null))
    println(map.equals("not a map"))
    println(map.hashCode() == ProbeMap().hashCode())
    println(map.toString())

    val empty: AbstractMap<String, Int?> = EmptyMap()
    println(empty.size)
    println(empty.isEmpty())
    println(empty.keys)
    println(empty.values)
    println(empty.toString())
}
