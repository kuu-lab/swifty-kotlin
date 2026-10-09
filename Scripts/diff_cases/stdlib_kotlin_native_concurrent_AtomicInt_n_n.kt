// CANDIDATE-ONLY: JVM kotlinc has no Kotlin/Native AtomicInt oracle (DEBT-DIFF-001).
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.AtomicInt

fun main() {
    AtomicInt(42)
}
