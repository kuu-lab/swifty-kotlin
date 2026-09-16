// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

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

fun main() {}
