/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractMap.kt.
 */

package kotlin.collections

// KSP-928: the nominal AbstractMap declaration and its skeletal read-only
// operations are source-backed. Map allocation, entry materialization, and
// shared collection runtime bridges remain compiler/runtime-owned.

private fun <K, V> abstractMapKeys(entries: Set<Map.Entry<K, V>>): Set<K> {
    val result = mutableSetOf<K>()
    for (entry in entries) {
        result.add(entry.key)
    }
    return result
}

private fun <K, V> abstractMapValues(entries: Set<Map.Entry<K, V>>): Collection<V> {
    val result = mutableListOf<V>()
    for (entry in entries) {
        result.add(entry.value)
    }
    return result
}

/**
 * Provides a skeletal implementation of the read-only [Map] interface.
 */
public abstract class AbstractMap<K, out V> protected constructor() : Map<K, V> {
    protected abstract val entries: Set<Map.Entry<K, V>>

    override fun containsKey(key: K): Boolean {
        for (entry in entries) {
            if (entry.key == key) return true
        }
        return false
    }

    override fun containsValue(value: @UnsafeVariance V): Boolean {
        for (entry in entries) {
            if (entry.value == value) return true
        }
        return false
    }

    override operator fun get(key: K): V? {
        for (entry in entries) {
            if (entry.key == key) return entry.value
        }
        return null
    }

    override val size: Int
        get() = entries.size

    override fun isEmpty(): Boolean = size == 0

    override val keys: Set<K>
        get() = abstractMapKeys(entries)

    override val values: Collection<V>
        get() = abstractMapValues(entries)

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other is AbstractMap<*, *>) {
            @Suppress("UNCHECKED_CAST")
            val otherEntries = other.entries as Set<Map.Entry<Any?, Any?>>
            @Suppress("UNCHECKED_CAST")
            val leftEntries = entries as Set<Map.Entry<Any?, Any?>>
            if (leftEntries.size != otherEntries.size) return false
            for (entry in leftEntries) {
                var found = false
                for (otherEntry in otherEntries) {
                    if (otherEntry.key == entry.key && otherEntry.value == entry.value) {
                        found = true
                        break
                    }
                }
                if (!found) return false
            }
            return true
        }
        if (other !is Map<*, *>) return false
        @Suppress("UNCHECKED_CAST")
        val leftEntries = entries as Set<Map.Entry<Any?, Any?>>
        @Suppress("UNCHECKED_CAST")
        val typedOther = other as Map<Any?, Any?>
        if (leftEntries.size != typedOther.count) return false
        for (entry in leftEntries) {
            if (!typedOther.containsKey(entry.key)) return false
            if (typedOther[entry.key] != entry.value) return false
        }
        return true
    }

    override fun hashCode(): Int {
        var result = 0
        for (entry in entries) {
            result += entry.key.hashCode() xor entry.value.hashCode()
        }
        return result
    }

    override fun toString(): String {
        @Suppress("UNCHECKED_CAST")
        val typedEntries = entries as Set<Map.Entry<Any?, Any?>>
        return mapEntriesToString(typedEntries.toList(), 0)
    }

    private fun mapEntriesToString(entries: List<Map.Entry<Any?, Any?>>, index: Int): String {
        if (index >= entries.size) return "}"
        val entry = entries[index]
        val separator = if (index == 0) "{" else ", "
        return separator + mapValueToString(entry.key) + "=" + mapValueToString(entry.value) +
            mapEntriesToString(entries, index + 1)
    }

    private fun mapValueToString(value: Any?): String =
        if (value === this) "(this Map)" else if (value == null) "null" else "$value"
}
