@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicReference

fun constructAtomicReference(value: String): AtomicReference<String> = AtomicReference(value)
