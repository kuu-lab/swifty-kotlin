package kotlin.js.collections

import kotlin.collections.Map
import kotlin.collections.MutableMap
import kotlin.collections.List
import kotlin.collections.MutableList
import kotlin.collections.MutableSet
import kotlin.collections.Set
import kotlin.collections.toMap
import kotlin.collections.toList
import kotlin.collections.toMutableMap
import kotlin.collections.toMutableList
import kotlin.collections.toMutableSet
import kotlin.collections.toSet
import kotlin.js.ExperimentalJsCollectionsApi

@PublishedApi
internal class JsCollectionViewBacking<out T>(
    @PublishedApi internal val value: T
)

@SinceKotlin("2.0")
public open class JsReadonlyMap<K, out V> internal constructor(
    @PublishedApi internal val view: JsCollectionViewBacking<Map<K, @UnsafeVariance V>>
)

@SinceKotlin("2.0")
public open class JsReadonlyArray<out E> internal constructor(
    @PublishedApi internal val view: JsCollectionViewBacking<List<E>>
)

@SinceKotlin("2.0")
public open class JsMap<K, V> internal constructor(
    view: JsCollectionViewBacking<MutableMap<K, V>>
) : JsReadonlyMap<K, V>(view)

@SinceKotlin("2.0")
public open class JsReadonlySet<out E> internal constructor(
    @PublishedApi internal val view: JsCollectionViewBacking<Set<@UnsafeVariance E>>
)

@SinceKotlin("2.0")
public open class JsSet<E> internal constructor(
    view: JsCollectionViewBacking<MutableSet<E>>
) : JsReadonlySet<E>(view)

@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <K, V> JsReadonlyMap<K, V>.toMap(): Map<K, V> = view.value.toMap()

@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <K, V> JsReadonlyMap<K, V>.toMutableMap(): MutableMap<K, V> =
    view.value.toMutableMap()

@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <E> JsReadonlyArray<E>.toList(): List<E> = view.value.toList()

@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <E> JsReadonlyArray<E>.toMutableList(): MutableList<E> = view.value.toMutableList()

@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <E> JsReadonlySet<E>.toSet(): Set<E> = view.value.toSet()

@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <E> JsReadonlySet<E>.toMutableSet(): MutableSet<E> =
    view.value.toMutableSet()

@PublishedApi
internal fun <K, V> createJsMapViewFrom(map: MutableMap<K, V>): JsMap<K, V> =
    JsMap(JsCollectionViewBacking(map))

@PublishedApi
internal fun <E> createJsReadonlyArrayViewFrom(list: List<E>): JsReadonlyArray<E> =
    JsReadonlyArray(JsCollectionViewBacking(list))

@PublishedApi
internal fun <E> createJsSetViewFrom(set: MutableSet<E>): JsSet<E> =
    JsSet(JsCollectionViewBacking(set))
