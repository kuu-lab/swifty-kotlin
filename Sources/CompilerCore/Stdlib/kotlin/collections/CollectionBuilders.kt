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
