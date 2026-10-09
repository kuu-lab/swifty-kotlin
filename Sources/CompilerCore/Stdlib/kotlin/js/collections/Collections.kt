package kotlin.js.collections

import kotlin.collections.Map
import kotlin.collections.MutableMap
import kotlin.collections.toMap
import kotlin.collections.toMutableMap
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

/** Copies the entries from this view into a Kotlin map. */
@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <K, V> JsReadonlyMap<K, V>.toMap(): Map<K, V> = view.value.toMap()

/** Copies the entries from this view into a mutable Kotlin map. */
@ExperimentalJsCollectionsApi
@SinceKotlin("2.0")
public inline fun <K, V> JsReadonlyMap<K, V>.toMutableMap(): MutableMap<K, V> =
    view.value.toMutableMap()

@PublishedApi
internal fun <K, V> createJsMapViewFrom(map: MutableMap<K, V>): JsMap<K, V> =
    JsMap(JsCollectionViewBacking(map))
