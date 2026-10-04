// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.BitSet is Kotlin/Native-only and has no JVM kotlinc counterpart.
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
