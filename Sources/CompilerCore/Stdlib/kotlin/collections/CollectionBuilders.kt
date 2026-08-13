package kotlin.collections

// MIGRATION-COL-011
// Builder DSL functions for collections.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticBuilderDSLStubs.swift

// ─── buildList ────────────────────────────────────────────────────────────────

@kotlin.experimental.ExperimentalTypeInference
public fun <E> buildList(builderAction: MutableList<E>.() -> Unit): List<out E> {
    val result = mutableListOf<E>()
    result.builderAction()
    return result
}

@kotlin.experimental.ExperimentalTypeInference
public fun <E> buildList(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<out E> {
    val result = mutableListOf<E>()
    result.builderAction()
    return result
}

// ─── buildSet ─────────────────────────────────────────────────────────────────

@kotlin.experimental.ExperimentalTypeInference
public fun <E> buildSet(builderAction: MutableSet<E>.() -> Unit): Set<out E> {
    val result = mutableSetOf<E>()
    result.builderAction()
    return result
}

@kotlin.experimental.ExperimentalTypeInference
public fun <E> buildSet(capacity: Int, builderAction: MutableSet<E>.() -> Unit): Set<out E> {
    val result = mutableSetOf<E>()
    result.builderAction()
    return result
}

// ─── buildMap ─────────────────────────────────────────────────────────────────

@kotlin.experimental.ExperimentalTypeInference
public fun <K, V> buildMap(builderAction: MutableMap<K, V>.() -> Unit): Map<out K, out V> {
    val result = mutableMapOf<K, V>()
    result.builderAction()
    return result
}

@kotlin.experimental.ExperimentalTypeInference
public fun <K, V> buildMap(capacity: Int, builderAction: MutableMap<K, V>.() -> Unit): Map<out K, out V> {
    val result = mutableMapOf<K, V>()
    result.builderAction()
    return result
}
