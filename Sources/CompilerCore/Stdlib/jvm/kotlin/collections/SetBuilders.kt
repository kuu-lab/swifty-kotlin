@file:kotlin.jvm.JvmName("SetsKt")
package kotlin.collections

import kotlin.collections.builders.RepositorySetBuilder
import kotlin.contracts.contract
import kotlin.contracts.InvocationKind

@PublishedApi
internal fun <E> createSetBuilder(): MutableSet<E> = RepositorySetBuilder<E>(8)
@PublishedApi
internal fun <E> createSetBuilder(capacity: Int): MutableSet<E> = RepositorySetBuilder<E>(capacity)
@PublishedApi
internal fun <E> build(builder: MutableSet<E>): Set<E> {
    (builder as RepositorySetBuilder<E>).freeze()
    return if (builder.isEmpty()) emptySet<E>() else builder
}

public inline fun <E> buildSet(builderAction: MutableSet<E>.() -> Unit): Set<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createSetBuilder<E>()
    result.builderAction()
    return build(result)
}

public inline fun <E> buildSet(capacity: Int, builderAction: MutableSet<E>.() -> Unit): Set<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createSetBuilder<E>(capacity)
    result.builderAction()
    return build(result)
}
