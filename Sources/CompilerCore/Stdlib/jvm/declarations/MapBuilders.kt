@file:kotlin.jvm.JvmName("MapsKt")
package kotlin.collections

import kotlin.contracts.contract
import kotlin.contracts.InvocationKind

@PublishedApi
internal fun <K, V> createMapBuilder(): MutableMap<K, V> = null!!
@PublishedApi
internal fun <K, V> createMapBuilder(capacity: Int): MutableMap<K, V> = null!!
@PublishedApi
internal fun <K, V> build(builder: MutableMap<K, V>): Map<K, V> = null!!
@kotlin.experimental.ExperimentalTypeInference
public inline fun <K, V> buildMap(builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createMapBuilder<K, V>()
    result.builderAction()
    return build(result)
}
@kotlin.experimental.ExperimentalTypeInference
public inline fun <K, V> buildMap(capacity: Int, builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createMapBuilder<K, V>(capacity)
    result.builderAction()
    return build(result)
}
