package kotlin.collections

// MIGRATION-SETMAP-001
// Set basic operations migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSetAndMap.swift
//   (kk_set_contains, kk_set_size, kk_set_is_empty)
// Synthetic stubs: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticSetStubs.swift
//   (registerSetContainsMember, registerSetIsEmptyMember)
// Lowering dispatch: Sources/CompilerCore/KIR/CallLowerer+UnresolvedMemberCalls.swift
//   (size → kk_set_size, isEmpty → kk_set_is_empty)
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// Sema stubs and the lowering-pass special-casing in unresolvedCollectionMemberCallee
// still route these call sites to kk_* ABI functions. This file is the migration
// target; wiring (and removal of synthetic stubs and lowering special-cases) happens
// in RF-STDLIB-004+.
//
// Implementation strategy:
//   - contains(element) — ABI bridge kk_set_contains
//   - size              — ABI bridge kk_set_size
//   - isEmpty()         — derived: size == 0 (no separate ABI bridge needed)

// ─── ABI bridges ─────────────────────────────────────────────────────────────
//
// Map directly to @_cdecl functions in RuntimeSetAndMap.swift.
// kk_set_contains returns Boolean (1/0 coerced by the compiler ABI layer).
// kk_set_size returns Int.

private external fun kk_set_contains(setRaw: Any?, element: Any?): Boolean
private external fun kk_set_size(setRaw: Any?): Int

// ─── contains ────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: operator fun contains(element: @UnsafeVariance E): Boolean
// Declared as interface member in Collection<E>; this extension shadows it once
// the sema stub (registerSetContainsMember) is removed in RF-STDLIB-004+.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public operator fun <T> Set<T>.contains(element: T): Boolean =
    kk_set_contains(this, element)

// ─── size ────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: val size: Int
// Declared as interface property on Collection<E>; dispatched via
// unresolvedCollectionMemberCallee → kk_set_size until wired.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public val <T> Set<T>.size: Int
    get() = kk_set_size(this)

// ─── isEmpty ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun isEmpty(): Boolean
// Declared as interface method on Collection<E>; derived from size so no
// separate ABI bridge is needed.

@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
public fun <T> Set<T>.isEmpty(): Boolean = size == 0
