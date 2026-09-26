// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent.atomics is Native-only
// in Kotlin 2.3.10 and is unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicArray

fun fetchAndUpdateAt(atomic: AtomicArray<String>, transform: (String) -> String): String =
    atomic.fetchAndUpdateAt(0, transform)

fun updateAt(atomic: AtomicArray<String>, transform: (String) -> String): Unit =
    atomic.updateAt(0, transform)

fun updateAndFetchAt(atomic: AtomicArray<String>, transform: (String) -> String): String =
    atomic.updateAndFetchAt(0, transform)

fun main() {}
