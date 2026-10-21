@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.contracts.contract
import kotlin.contracts.InvocationKind

@PublishedApi
internal fun <E> createListBuilder(): MutableList<E> = null!!
@PublishedApi
internal fun <E> createListBuilder(capacity: Int): MutableList<E> = null!!
@PublishedApi
internal fun <E> build(builder: MutableList<E>): List<E> = null!!
@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildList(builderAction: MutableList<E>.() -> Unit): List<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createListBuilder<E>()
    result.builderAction()
    return build(result)
}
@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildList(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createListBuilder<E>(capacity)
    result.builderAction()
    return build(result)
}
