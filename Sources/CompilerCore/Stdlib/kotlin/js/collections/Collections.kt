package kotlin.js.collections

import kotlin.collections.Map
import kotlin.collections.MutableMap
import kotlin.collections.MutableSet
import kotlin.collections.Set
import kotlin.collections.toMap
import kotlin.collections.toMutableMap
import kotlin.collections.toMutableSet
import kotlin.collections.toSet
import kotlin.js.ExperimentalJsCollectionsApi

/** Shared storage used by the native compatibility wrappers for JS collection views. */
@PublishedApi
internal class JsCollectionViewBacking<out T>(
    @PublishedApi internal val value: T
)

/** Opaque native compatibility wrapper for a JavaScript readonly map view. */
@SinceKotlin("2.0")
public open class JsReadonlyMap<K, out V> internal constructor(
    @PublishedApi internal val view: JsCollectionViewBacking<Map<K, @UnsafeVariance V>>
)

/** Opaque native compatibility wrapper for a JavaScript mutable map view. */
@SinceKotlin("2.0")
public open class JsMap<K, V> internal constructor(
    view: JsCollectionViewBacking<MutableMap<K, V>>
) : JsReadonlyMap<K, V>(view)

/** Opaque native compatibility wrapper for a JavaScript readonly set view. */
@SinceKotlin("2.0")
public open class JsReadonlySet<out E> internal constructor(
    @PublishedApi internal val view: JsCollectionViewBacking<Set<@UnsafeVariance E>>
)

/** Opaque native compatibility wrapper for a JavaScript mutable set view. */
@SinceKotlin("2.0")
public open class JsSet<E> internal constructor(
    view: JsCollectionViewBacking<MutableSet<E>>
) : JsReadonlySet<E>(view)

/** Copies the entries from this view into a Kotlin map. */
@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <K, V> JsReadonlyMap<K, V>.toMap(): Map<K, V> = view.value.toMap()

/** Copies the entries from this view into a mutable Kotlin map. */
@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <K, V> JsReadonlyMap<K, V>.toMutableMap(): MutableMap<K, V> =
    view.value.toMutableMap()

/** Copies the elements from this view into a Kotlin set. */
@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <E> JsReadonlySet<E>.toSet(): Set<E> = view.value.toSet()

/** Copies the elements from this view into a mutable Kotlin set. */
@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <E> JsReadonlySet<E>.toMutableSet(): MutableSet<E> =
    view.value.toMutableSet()

@PublishedApi
internal fun <K, V> createJsMapViewFrom(map: MutableMap<K, V>): JsMap<K, V> =
    JsMap(JsCollectionViewBacking(map))

@PublishedApi
internal fun <E> createJsSetViewFrom(set: MutableSet<E>): JsSet<E> =
    JsSet(JsCollectionViewBacking(set))
