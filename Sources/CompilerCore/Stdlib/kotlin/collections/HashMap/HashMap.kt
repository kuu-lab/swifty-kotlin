/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/native-wasm/src/kotlin/collections/HashMap.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual

// KUU-556: open, so LinkedHashMap.kt can be a real subclass (matching the
// diff oracle's kotlinc-jvm reference, where java.util.LinkedHashMap extends
// java.util.HashMap) instead of a typealias onto an unrelated interface.

// KUU-1941: base implementations use a native storage handle, while calls on
// the Kotlin object retain interface dispatch to user overrides.
@KsSymbolName("__kk_hash_map_storage")
private external fun <K, V> __hashMapStorage(map: HashMap<K, V>): MutableMap<K, V>

@KsSymbolName("__kk_map_size")
private external fun <K, V> __hashMapSize(map: MutableMap<K, V>): Int

@KsSymbolName("__kk_map_is_empty")
private external fun <K, V> __hashMapIsEmpty(map: MutableMap<K, V>): Boolean

@KsSymbolName("__kk_map_get")
private external fun <K, V> __hashMapGet(map: MutableMap<K, V>, key: K): V?

@KsSymbolName("__kk_mutable_map_put")
private external fun <K, V> __hashMapPut(map: MutableMap<K, V>, key: K, value: V): V?

@KsSymbolName("__kk_mutable_map_remove")
private external fun <K, V> __hashMapRemove(map: MutableMap<K, V>, key: K): V?

@KsSymbolName("__kk_mutable_map_clear")
private external fun <K, V> __hashMapClear(map: MutableMap<K, V>)

@KsSymbolName("__kk_map_entries")
private external fun <K, V> __hashMapEntries(map: MutableMap<K, V>): MutableSet<MutableMap.MutableEntry<K, V>>

@KsSymbolName("__kk_map_keys")
private external fun <K, V> __hashMapKeys(map: MutableMap<K, V>): MutableSet<K>

@KsSymbolName("__kk_map_values")
private external fun <K, V> __hashMapValues(map: MutableMap<K, V>): MutableCollection<V>

@KsSymbolName("__kk_builder_map_freeze")
private external fun <K, V> __hashMapFreeze(map: MutableMap<K, V>): Map<K, V>

public open class HashMap<K, V> : MutableMap<K, V> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(initialCapacity: Int, loadFactor: Float)
    constructor(original: Map<out K, V>)

    @PublishedApi
    internal fun build(): Map<K, V> {
        __hashMapFreeze(__hashMapStorage(this))
        return this
    }

    override fun clear() {
        __hashMapClear(__hashMapStorage(this))
    }

    override fun containsKey(key: K): Boolean {
        for (entry in entries) {
            if (__valuesEqual(entry.key, key)) return true
        }
        return false
    }

    override fun containsValue(value: V): Boolean {
        for (entry in entries) {
            if (__valuesEqual(entry.value, value)) return true
        }
        return false
    }

    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = __hashMapEntries(__hashMapStorage(this))

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Map<*, *>) return false
        val thisEntries = entries
        val otherEntries = other.entries
        if (thisEntries.size != otherEntries.size) return false

        for (entry in thisEntries) {
            var found = false
            for (otherEntry in otherEntries) {
                if (__valuesEqual(entry.key, otherEntry.key)) {
                    if (!__valuesEqual(entry.value, otherEntry.value)) return false
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return true
    }

    override operator fun get(key: K): V? = __hashMapGet(__hashMapStorage(this), key)

    override fun hashCode(): Int {
        var result = 0
        for (entry in entries) {
            val keyHash = entry.key?.hashCode() ?: 0
            val valueHash = entry.value?.hashCode() ?: 0
            result += keyHash xor valueHash
        }
        return result
    }

    override fun isEmpty(): Boolean = __hashMapIsEmpty(__hashMapStorage(this))

    override val keys: MutableSet<K>
        get() = __hashMapKeys(__hashMapStorage(this))

    @IgnorableReturnValue
    override fun put(key: K, value: V): V? = __hashMapPut(__hashMapStorage(this), key, value)

    override fun putAll(from: Map<out K, V>) {
        for (entry in from.entries) {
            put(entry.key, entry.value)
        }
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? = __hashMapRemove(__hashMapStorage(this), key)

    override val size: Int
        get() = __hashMapSize(__hashMapStorage(this))

    override fun toString(): String {
        val builder = StringBuilder()
        builder.append("{")
        var first = true
        for (entry in entries) {
            if (!first) builder.append(", ")
            first = false
            if (entry.key === this) {
                builder.append("(this Map)")
            } else {
                builder.append(entry.key?.toString() ?: "null")
            }
            builder.append("=")
            if (entry.value === this) {
                builder.append("(this Map)")
            } else {
                builder.append(entry.value?.toString() ?: "null")
            }
        }
        builder.append("}")
        return builder.toString()
    }

    override val values: MutableCollection<V>
        get() = __hashMapValues(__hashMapStorage(this))
}
