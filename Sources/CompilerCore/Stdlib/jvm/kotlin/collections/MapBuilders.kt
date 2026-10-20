@file:kotlin.jvm.JvmName("MapsKt")
package kotlin.collections

import kotlin.contracts.contract
import kotlin.contracts.InvocationKind

@PublishedApi
internal fun <K, V> createMapBuilder(): MutableMap<K, V> = kotlin.collections.builders.RepositoryMapBuilder<K, V>(8)
@PublishedApi
internal fun <K, V> createMapBuilder(capacity: Int): MutableMap<K, V> {
    if (capacity < 0) throw IllegalArgumentException("capacity must be non-negative.")
    return kotlin.collections.builders.RepositoryMapBuilder<K, V>(capacity)
}
@PublishedApi
internal fun <K, V> build(builder: MutableMap<K, V>): Map<K, V> {
    (builder as kotlin.collections.builders.RepositoryMapBuilder<K, V>).freeze()
    return if (builder.size == 0) kotlin.collections.builders.RepositoryEmptyMapBuilder.value as Map<K, V> else builder
}
public inline fun <K, V> buildMap(builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createMapBuilder<K, V>()
    result.builderAction()
    return build(result)
}
public inline fun <K, V> buildMap(capacity: Int, builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createMapBuilder<K, V>(capacity)
    result.builderAction()
    return build(result)
}
