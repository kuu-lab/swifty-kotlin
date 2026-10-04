package kotlin.collections

import kotlin.internal.KsSymbolName

public interface MutableMap<K, V> : Map<K, V> {
    public interface MutableEntry<K, V> : Map.Entry<K, V>

    public override val keys: MutableSet<K>
    public override val values: MutableCollection<V>
    public override val entries: MutableSet<MutableMap.MutableEntry<K, V>>

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_map_remove")
    public fun remove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    public fun clear()
}
