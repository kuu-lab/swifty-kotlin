@file:kotlin.jvm.JvmName("SetsKt")
package kotlin.collections

import kotlin.contracts.contract
import kotlin.contracts.InvocationKind

@PublishedApi
internal fun <E> createSetBuilder(): MutableSet<E> = null!!
@PublishedApi
internal fun <E> createSetBuilder(capacity: Int): MutableSet<E> = null!!
@PublishedApi
internal fun <E> build(builder: MutableSet<E>): Set<E> = null!!

@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildSet(builderAction: MutableSet<E>.() -> Unit): Set<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createSetBuilder<E>()
    result.builderAction()
    return build(result)
}

@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildSet(capacity: Int, builderAction: MutableSet<E>.() -> Unit): Set<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createSetBuilder<E>(capacity)
    result.builderAction()
    return build(result)
}
