package kotlin.collections

import kotlin.internal.KsSymbolName

public interface MutableMap<K, V> : Map<K, V> {
    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_map_remove")
    public fun remove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    public fun clear()
}
