@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicInt

fun constructAtomicInt(value: Int): AtomicInt = AtomicInt(value)
