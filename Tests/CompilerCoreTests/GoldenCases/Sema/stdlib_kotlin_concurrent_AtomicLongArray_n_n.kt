@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicLongArray

fun atomicLongArrayFromSize(size: Int): AtomicLongArray = AtomicLongArray(size)
fun atomicLongArrayFromStorage(values: LongArray): AtomicLongArray = AtomicLongArray(values)
