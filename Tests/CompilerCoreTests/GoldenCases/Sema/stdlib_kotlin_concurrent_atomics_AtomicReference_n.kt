@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicReference

fun atomicReferenceFetchAndUpdate(transform: (String) -> String): String {
    val atomic = AtomicReference("initial")
    return atomic.fetchAndUpdate(transform)
}

fun atomicReferenceUpdate(transform: (String) -> String): Unit {
    val atomic = AtomicReference("initial")
    atomic.update(transform)
}

fun atomicReferenceUpdateAndFetch(transform: (String) -> String): String {
    val atomic = AtomicReference("initial")
    return atomic.updateAndFetch(transform)
}
