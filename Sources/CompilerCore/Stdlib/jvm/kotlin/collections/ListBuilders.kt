@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.contracts.contract
import kotlin.contracts.InvocationKind

@PublishedApi
internal fun <E> createListBuilder(): MutableList<E> = kotlin.collections.builders.RepositoryListBuilder<E>(10)
@PublishedApi
internal fun <E> createListBuilder(capacity: Int): MutableList<E> {
    if (capacity < 0) throw IllegalArgumentException("capacity must be non-negative.")
    return kotlin.collections.builders.RepositoryListBuilder<E>(capacity)
}
@PublishedApi
internal fun <E> build(builder: MutableList<E>): List<E> {
    (builder as kotlin.collections.builders.RepositoryListBuilder<E>).freeze()
    return if (builder.size == 0) kotlin.collections.builders.RepositoryEmptyListBuilder.value as List<E> else builder
}
public inline fun <E> buildList(builderAction: MutableList<E>.() -> Unit): List<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createListBuilder<E>()
    result.builderAction()
    return build(result)
}
public inline fun <E> buildList(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<E> {
    contract { callsInPlace(builderAction, InvocationKind.EXACTLY_ONCE) }
    val result = createListBuilder<E>(capacity)
    result.builderAction()
    return build(result)
}
