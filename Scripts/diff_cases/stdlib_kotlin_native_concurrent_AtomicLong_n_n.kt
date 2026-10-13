// CANDIDATE-ONLY: kotlin.native.concurrent APIs are unavailable in JVM kotlinc.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.AtomicLong

fun main() {
    AtomicLong()
    AtomicLong(42L)
}
