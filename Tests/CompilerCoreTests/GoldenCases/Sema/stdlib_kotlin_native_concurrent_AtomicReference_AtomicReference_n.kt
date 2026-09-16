@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.AtomicReference

fun atomicReferenceValue(reference: AtomicReference<String>): String = reference.value

fun atomicReferenceGetAndSet(
    reference: AtomicReference<String>,
    newValue: String
): String = reference.getAndSet(newValue)

fun atomicReferenceCompareAndSwap(
    reference: AtomicReference<String>,
    expected: String,
    newValue: String
): String = reference.compareAndSwap(expected, newValue)

fun atomicReferenceToString(reference: AtomicReference<String>): String = reference.toString()
