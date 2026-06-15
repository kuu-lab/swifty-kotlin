package kotlin.collections

// MIGRATION-COL-011
// Builder DSL functions for collections.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticBuilderDSLStubs.swift
//   (registerSyntheticBuildListStub / registerSyntheticBuildSetStub / registerSyntheticBuildMapStub)
//
// Runtime implementation: Sources/Runtime/RuntimeBuilderDSL.swift
//   kk_build_list / kk_build_list_with_capacity / kk_build_set / kk_build_map
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// CollectionLiteralLoweringPass intercepts all builder DSL call sites and
// rewrites them to kk_build_* ABI calls (STDLIB-002). The synthetic stubs in
// HeaderHelpers+SyntheticBuilderDSLStubs.swift continue to provide type
// information until this file is loaded. Wiring (and removal of the synthetic
// stubs) happens in RF-STDLIB-004+.
//
// Unlike CollectionFactories.kt, these functions cannot use `private external`
// ABI bridges because the kk_build_* runtime functions take a compiled function
// pointer (Int), not the Kotlin-level lambda receiver type. The pure Kotlin
// bodies below are correct fallback implementations that work once wired.

// ─── buildList ────────────────────────────────────────────────────────────────

public fun <E> buildList(builderAction: MutableList<E>.() -> Unit): List<E> {
    val result = mutableListOf<E>()
    result.builderAction()
    return result
}

public fun <E> buildList(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<E> {
    val result = mutableListOf<E>()
    result.builderAction()
    return result
}

// ─── buildSet ────────────────────────────────────────────────────────────────

public fun <E> buildSet(builderAction: MutableSet<E>.() -> Unit): Set<E> {
    val result = mutableSetOf<E>()
    result.builderAction()
    return result
}

// ─── buildMap ────────────────────────────────────────────────────────────────

public fun <K, V> buildMap(builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> {
    val result = mutableMapOf<K, V>()
    result.builderAction()
    return result
}
