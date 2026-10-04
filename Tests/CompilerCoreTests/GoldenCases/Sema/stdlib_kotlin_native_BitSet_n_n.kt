@file:OptIn(kotlin.native.ObsoleteNativeApi::class)

package golden.sema

import kotlin.native.BitSet

fun bitSetConstructors(): Int {
    var initializerCalls = 0
    val empty = BitSet()
    val zero = BitSet(0)
    val negative = BitSet(-1)
    val initialized = BitSet(5) {
        initializerCalls += 1
        it == 0 || it == 4
    }
    val sized = BitSet(5)
    return if (
        BitSet.Companion === BitSet.Companion &&
        empty !== sized &&
        zero !== negative &&
        initialized !== empty
    ) {
        initializerCalls
    } else {
        -1
    }
}
