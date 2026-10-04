package golden.sema

import kotlin.collections.AbstractMap
import kotlin.collections.Collection
import kotlin.collections.Map
import kotlin.collections.Set

class ProbeMap : AbstractMap<String, Int?>() {
    override val entries: Set<Map.Entry<String, Int?>>
        get() = emptyMap<String, Int?>().entries
}

fun abstractMapSurface(
    values: AbstractMap<String, Int?>,
    other: Any?,
    key: String,
    amount: Int?
): Int? {
    values.containsKey(key)
    values.containsValue(amount)
    values.equals(other)
    values.get(key)
    values[key]
    values.hashCode()
    values.isEmpty()
    values.toString()
    val keys: Set<String> = values.keys
    val size: Int = values.size
    val valuesView: Collection<Int?> = values.values
    keys.contains(key)
    valuesView.contains(amount)
    return size
}
