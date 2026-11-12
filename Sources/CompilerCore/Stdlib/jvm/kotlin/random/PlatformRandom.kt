package kotlin.random

import kotlin.jvm.internal.__jvmThreadLocalRandom
import kotlin.jvm.internal.__jvmThreadLocalRandomNextInt

private class JVMDefaultRandom : Random() {
    override fun nextInt(): Int = __jvmThreadLocalRandomNextInt(__jvmThreadLocalRandom())
    override fun nextBits(bitCount: Int): Int = nextInt().takeUpperBits(bitCount)
}

internal fun platformDefaultRandom(): Random = JVMDefaultRandom()
