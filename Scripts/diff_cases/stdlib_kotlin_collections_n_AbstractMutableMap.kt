// KSP-930: keep the source-backed AbstractMutableMap class shell compatible
// with kotlinc, including Map/MutableMap supertype use and inherited map views.

import kotlin.collections.AbstractMutableMap
import kotlin.collections.Map
import kotlin.collections.MutableMap

abstract class ProbeMutableMap : AbstractMutableMap<String, Int>()

fun inheritedMapSurface(values: ProbeMutableMap, missing: String): Int? {
    val readonly: Map<String, Int> = values
    val mutable: MutableMap<String, Int> = values
    val missingValue = readonly[missing]
    mutable.putAll(emptyMap<String, Int>())
    mutable.remove(missing)
    val keyView = mutable.keys
    val valueView = mutable.values
    val entryView = readonly.entries
    values.equals(readonly)
    values.hashCode()
    values.toString()
    keyView.size
    valueView.size
    entryView.size
    return missingValue
}

fun main() {
    val map: MutableMap<String, Int> = mutableMapOf("present" to 7)
    println(map["missing"] == null)
    map.put("added", 9)
    map.remove("present")
    println(map.keys.size)
    println(map.values.size)
    println(map.entries.size)
    println(map.toString())
}
