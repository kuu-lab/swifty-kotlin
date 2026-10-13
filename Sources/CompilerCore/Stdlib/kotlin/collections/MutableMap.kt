package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.js.ExperimentalJsCollectionsApi
import kotlin.js.ExperimentalJsExport
import kotlin.js.collections.JsMap
import kotlin.js.collections.createJsMapViewFrom

public interface MutableMap<K, V> : Map<K, V> {
    public interface MutableEntry<K, V> : Map.Entry<K, V> {
        /** Replaces the value associated with this entry and returns the previous value. */
        @IgnorableReturnValue
        public fun setValue(newValue: V): V
    }

    public override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
    public override val keys: MutableSet<K>
    public override val values: MutableCollection<V>

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_map_put")
    public fun put(key: K, value: V): V?

    @KsSymbolName("__kk_mutable_map_putAll")
    public fun putAll(from: Map<out K, V>)

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_map_remove")
    public fun remove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    public fun clear()

    /** Returns a typed view that keeps this map as its shared backing state. */
    @ExperimentalJsExport
    @ExperimentalJsCollectionsApi
    @SinceKotlin("2.0")
    public fun asJsMapView(): JsMap<K, V> = createJsMapViewFrom(this)
}
