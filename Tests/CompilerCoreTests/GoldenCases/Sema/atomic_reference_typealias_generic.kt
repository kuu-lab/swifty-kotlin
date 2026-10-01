@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicReference

fun appendAtomically(atomic: AtomicReference<String>): String =
    atomic.fetchAndUpdate { it + "x" }

fun readNullable(atomic: AtomicReference<String?>): String? = atomic.load()
