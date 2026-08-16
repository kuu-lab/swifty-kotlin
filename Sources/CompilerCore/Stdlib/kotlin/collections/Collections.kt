package kotlin.collections

// KSP-435
// Generic Collection<T> conversions migrated from the Swift runtime
// `kk_collection_*` bridges. `size` / `isEmpty()` stay native because they are
// abstract interface members whose implementation depends on the runtime box
// type tag; they are reachable through the `__kk_collection_*` bridges.

@Suppress("UNCHECKED_CAST")
public fun <T> Collection<T>.toTypedArray(): Array<T> {
    val result = arrayOfNulls<Any?>(size)
    var index = 0
    for (element in this) {
        result[index] = element
        index++
    }
    return result as Array<T>
}
