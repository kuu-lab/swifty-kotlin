// CANDIDATE-ONLY: kotlin.native.BitSet is Kotlin/Native-only and has no JVM kotlinc counterpart.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_BitSet_n_n.expected.stdout
@file:OptIn(kotlin.native.ObsoleteNativeApi::class)

import kotlin.native.BitSet

fun main() {
    var initializerCalls = 0
    BitSet()
    BitSet(0)
    BitSet(-1)
    BitSet(5) {
        initializerCalls += 1
        it == 0 || it == 4
    }
    BitSet.Companion
    println("initializer-calls=$initializerCalls")
}
