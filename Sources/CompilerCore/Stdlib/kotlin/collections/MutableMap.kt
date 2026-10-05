package kotlin.collections

import kotlin.internal.KsSymbolName

public interface MutableMap<K, V> : Map<K, V> {
    public interface MutableEntry<K, V> : Map.Entry<K, V>

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
}
