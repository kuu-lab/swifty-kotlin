package kotlin.collections

// MIGRATION-COL-012
// Map higher-order function extension functions.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift (kk_map_filter,
//   kk_map_filterKeys, kk_map_filterValues, kk_map_mapKeys, kk_map_mapValues,
//   kk_map_mapNotNull, kk_map_flatMap, kk_map_forEach, kk_map_getOrElse) and
//   Sources/Runtime/RuntimeSetAndMap.swift (kk_map_getOrDefault).
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// HOF call sites are still intercepted by the lowering passes and rewritten to
// kk_* ABI calls. This file is the migration target; wiring (and removal of the
// corresponding sema stubs) happens in RF-STDLIB-004+.

// ─── filter ───────────────────────────────────────────────────────────────────

public fun <K, V> Map<K, V>.filter(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in entries) {
        if (predicate(entry)) {
            result[entry.key] = entry.value
        }
    }
    return result
}

// ─── filterKeys ───────────────────────────────────────────────────────────────

public fun <K, V> Map<K, V>.filterKeys(predicate: (K) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in entries) {
        if (predicate(entry.key)) {
            result[entry.key] = entry.value
        }
    }
    return result
}

// ─── filterValues ─────────────────────────────────────────────────────────────

public fun <K, V> Map<K, V>.filterValues(predicate: (V) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in entries) {
        if (predicate(entry.value)) {
            result[entry.key] = entry.value
        }
    }
    return result
}

// ─── mapKeys ──────────────────────────────────────────────────────────────────

public fun <K, V, R> Map<K, V>.mapKeys(transform: (Map.Entry<K, V>) -> R): Map<R, V> {
    val result = mutableMapOf<R, V>()
    for (entry in entries) {
        result[transform(entry)] = entry.value
    }
    return result
}

// ─── mapValues ────────────────────────────────────────────────────────────────

public fun <K, V, R> Map<K, V>.mapValues(transform: (Map.Entry<K, V>) -> R): Map<K, R> {
    val result = mutableMapOf<K, R>()
    for (entry in entries) {
        result[entry.key] = transform(entry)
    }
    return result
}

// ─── mapNotNull ───────────────────────────────────────────────────────────────

public fun <K, V, R : Any> Map<K, V>.mapNotNull(transform: (Map.Entry<K, V>) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (entry in entries) {
        val value = transform(entry)
        if (value != null) {
            result.add(value)
        }
    }
    return result
}

// ─── flatMap ──────────────────────────────────────────────────────────────────

public fun <K, V, R> Map<K, V>.flatMap(transform: (Map.Entry<K, V>) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (entry in entries) {
        for (item in transform(entry)) {
            result.add(item)
        }
    }
    return result
}

// ─── forEach ──────────────────────────────────────────────────────────────────

public fun <K, V> Map<K, V>.forEach(action: (Map.Entry<K, V>) -> Unit) {
    for (entry in entries) {
        action(entry)
    }
}

// ─── getOrElse ────────────────────────────────────────────────────────────────

public fun <K, V> Map<K, V>.getOrElse(key: K, defaultValue: () -> V): V {
    if (containsKey(key)) {
        @Suppress("UNCHECKED_CAST")
        return get(key) as V
    }
    return defaultValue()
}

// ─── getOrDefault ─────────────────────────────────────────────────────────────

public fun <K, V> Map<K, V>.getOrDefault(key: K, defaultValue: V): V {
    if (containsKey(key)) {
        @Suppress("UNCHECKED_CAST")
        return get(key) as V
    }
    return defaultValue
}
