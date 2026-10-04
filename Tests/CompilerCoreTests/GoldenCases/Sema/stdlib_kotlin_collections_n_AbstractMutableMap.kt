package golden.sema

import kotlin.collections.AbstractMutableMap
import kotlin.collections.Map
import kotlin.collections.MutableMap

abstract class ProbeMutableMap : AbstractMutableMap<String, Int>()

fun acceptReadonly(values: Map<String, Int>) {}

fun acceptMutable(values: MutableMap<String, Int>) {}

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
