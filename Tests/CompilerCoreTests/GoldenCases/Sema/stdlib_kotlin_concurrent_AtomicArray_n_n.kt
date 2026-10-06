@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicArray

fun atomicArrayFromInit(size: Int): AtomicArray<String> = AtomicArray(size) { it.toString() }
fun atomicArrayFromStorage(values: Array<String>): AtomicArray<String> = AtomicArray(values)
