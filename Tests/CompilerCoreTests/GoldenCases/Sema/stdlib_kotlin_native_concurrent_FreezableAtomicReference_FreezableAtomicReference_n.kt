@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.FreezableAtomicReference

fun freezableAtomicReferenceValue(reference: FreezableAtomicReference<String>): String = reference.value

fun freezableAtomicReferenceCompareAndSet(
    reference: FreezableAtomicReference<String>,
    expected: String,
    newValue: String
): Boolean = reference.compareAndSet(expected, newValue)

fun freezableAtomicReferenceCompareAndSwap(
    reference: FreezableAtomicReference<String>,
    expected: String,
    newValue: String
): String = reference.compareAndSwap(expected, newValue)

fun freezableAtomicReferenceToString(reference: FreezableAtomicReference<String>): String = reference.toString()
