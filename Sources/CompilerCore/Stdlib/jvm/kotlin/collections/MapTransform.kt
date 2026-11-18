@file:kotlin.jvm.JvmName("MapsKt")

package kotlin.collections

public inline fun <K, V, R> Map<out K, V>.map(transform: (Map.Entry<K, V>) -> R): List<R> {
    val result = mutableListOf<R>()
    for (entry in this) {
        result.add(transform(entry))
    }
    return result
}
