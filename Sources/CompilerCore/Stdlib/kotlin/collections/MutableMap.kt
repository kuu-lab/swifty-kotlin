package kotlin.collections

import kotlin.internal.KsSymbolName

public interface MutableMap<K, V> : Map<K, V> {
    public interface MutableEntry<K, V> : Map.Entry<K, V> {
        /** Replaces the value associated with this entry and returns the previous value. */
        @IgnorableReturnValue
        public fun setValue(newValue: V): V
    }

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_map_remove")
    public fun remove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    public fun clear()
}
