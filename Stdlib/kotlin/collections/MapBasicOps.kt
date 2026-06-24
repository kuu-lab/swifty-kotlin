package kotlin.collections

// MIGRATION-SETMAP-001
// Map basic operations migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSetAndMap.swift
//   (kk_map_contains_key, kk_map_contains_value, kk_map_get, kk_map_size,
//    kk_map_keys, kk_map_values, kk_map_entries, kk_map_is_empty)
// Synthetic stubs: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMapStubs.swift
//   (get, containsKey, containsValue, keys, values, entries, getOrDefault)
// Lowering dispatch: Sources/CompilerCore/KIR/CallLowerer+UnresolvedMemberCalls.swift
//   (size → kk_map_size, isEmpty → kk_map_is_empty)
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// Sema stubs and the lowering-pass special-casing in unresolvedCollectionMemberCallee
// still route these call sites to kk_* ABI functions. This file is the migration
// target; wiring (and removal of synthetic stubs and lowering special-cases) happens
// in RF-STDLIB-004+.
//
// Implementation strategy:
//   - containsKey(key)        — ABI bridge kk_map_contains_key
//   - containsValue(value)    — ABI bridge kk_map_contains_value
//   - get(key)                — ABI bridge kk_map_get (returns null for absent keys)
//   - getOrDefault(key, def)  — pure Kotlin in MapHOF.kt (MIGRATION-COL-012)
//   - keys                    — ABI bridge kk_map_keys
//   - values                  — ABI bridge kk_map_values
//   - entries                 — ABI bridge kk_map_entries
//   - size                    — ABI bridge kk_map_size
//   - isEmpty()               — derived: size == 0 (no separate ABI bridge needed)

// ─── ABI bridges ─────────────────────────────────────────────────────────────
//
// Map directly to @_cdecl functions in RuntimeSetAndMap.swift.
// Boolean-returning functions (containsKey, containsValue) return Boolean.
// kk_map_get returns Any? (null when key is absent).
// Collection-returning functions return Any? and are cast at the call site.

private external fun kk_map_contains_key(mapRaw: Any?, key: Any?): Boolean
private external fun kk_map_contains_value(mapRaw: Any?, value: Any?): Boolean
private external fun kk_map_get(mapRaw: Any?, key: Any?): Any?
private external fun kk_map_size(mapRaw: Any?): Int
private external fun kk_map_keys(mapRaw: Any?): Any?
private external fun kk_map_values(mapRaw: Any?): Any?
private external fun kk_map_entries(mapRaw: Any?): Any?

// ─── containsKey ─────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun containsKey(key: K): Boolean
// Interface member on Map<K, V>; this extension shadows it once the sema stub is
// removed in RF-STDLIB-004+.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public fun <K, V> Map<K, V>.containsKey(key: K): Boolean =
    kk_map_contains_key(this, key)

// ─── containsValue ───────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun containsValue(value: @UnsafeVariance V): Boolean
// Interface member on Map<K, V>.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public fun <K, V> Map<K, V>.containsValue(value: V): Boolean =
    kk_map_contains_value(this, value)

// ─── get ─────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: operator fun get(key: K): V?
// Interface member on Map<K, V>. Returns null when the key is absent (kk_map_get
// returns 0/null for missing keys).

@Suppress("EXTENSION_SHADOWED_BY_MEMBER", "UNCHECKED_CAST")
public operator fun <K, V> Map<K, V>.get(key: K): V? =
    kk_map_get(this, key) as V?

// ─── getOrDefault ─────────────────────────────────────────────────────────────
//
// Defined in Stdlib/kotlin/collections/MapHOF.kt (MIGRATION-COL-012) as a
// pure-Kotlin extension using containsKey and get:
//   if (containsKey(key)) get(key) as V else defaultValue
// The sema stub (kk_map_getOrDefault) remains active until RF-STDLIB-004+.

// ─── keys ────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: val keys: Set<K>
// Interface property on Map<K, V>.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER", "UNCHECKED_CAST")
public val <K, V> Map<K, V>.keys: Set<K>
    get() = kk_map_keys(this) as Set<K>

// ─── values ──────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: val values: Collection<V>
// Interface property on Map<K, V>.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER", "UNCHECKED_CAST")
public val <K, V> Map<K, V>.values: Collection<V>
    get() = kk_map_values(this) as Collection<V>

// ─── entries ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: val entries: Set<Map.Entry<K, V>>
// Interface property on Map<K, V>.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER", "UNCHECKED_CAST")
public val <K, V> Map<K, V>.entries: Set<Map.Entry<K, V>>
    get() = kk_map_entries(this) as Set<Map.Entry<K, V>>

// ─── size ────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: val size: Int
// Interface property on Map<K, V>; dispatched via unresolvedCollectionMemberCallee
// → kk_map_size until wired.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public val <K, V> Map<K, V>.size: Int
    get() = kk_map_size(this)

// ─── isEmpty ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun isEmpty(): Boolean
// Interface method on Map<K, V>; derived from size so no separate ABI bridge
// is needed.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public fun <K, V> Map<K, V>.isEmpty(): Boolean = size == 0
