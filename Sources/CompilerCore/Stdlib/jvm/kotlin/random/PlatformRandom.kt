package kotlin.random

import kotlin.jvm.internal.__jvmThreadLocalRandom
import kotlin.jvm.internal.__jvmThreadLocalRandomNextInt
import java.util.Random as JavaRandom

private class JVMDefaultRandom : Random() {
    override fun nextInt(): Int = __jvmThreadLocalRandomNextInt(__jvmThreadLocalRandom())
    override fun nextBits(bitCount: Int): Int = nextInt().takeUpperBits(bitCount)
}

internal fun platformDefaultRandom(): Random = JVMDefaultRandom()

private class JavaBackedRandom(val delegate: JavaRandom) : Random() {
    override fun nextBits(bitCount: Int): Int = delegate.nextInt().takeUpperBits(bitCount)
    override fun nextInt(): Int = delegate.nextInt()
    override fun nextInt(until: Int): Int = delegate.nextInt(until)
    override fun nextLong(): Long = delegate.nextLong()
    override fun nextBoolean(): Boolean = delegate.nextBoolean()
    override fun nextDouble(): Double = delegate.nextDouble()
    override fun nextFloat(): Float = delegate.nextFloat()

    override fun nextBytes(array: ByteArray): ByteArray {
        delegate.nextBytes(array)
        return array
    }
}

private class KotlinBackedRandom(delegate: Random) : JavaRandom() {
    private val target: Random? = delegate
    val delegate: Random get() = target!!

    protected override fun next(bits: Int): Int = delegate.nextBits(bits)
    override fun nextInt(): Int = delegate.nextInt()
    override fun nextInt(bound: Int): Int = delegate.nextInt(bound)
    override fun nextLong(): Long = delegate.nextLong()
    override fun nextBoolean(): Boolean = delegate.nextBoolean()
    override fun nextDouble(): Double = delegate.nextDouble()
    override fun nextFloat(): Float = delegate.nextFloat()

    override fun nextBytes(bytes: ByteArray) {
        delegate.nextBytes(bytes)
    }

    override fun setSeed(seed: Long) {
        // The Java superclass can call setSeed before assigning target.
        if (target != null) throw UnsupportedOperationException("Setting seed is not supported.")
    }
}

public fun JavaRandom.asKotlinRandom(): Random =
    if (this is KotlinBackedRandom) this.delegate else JavaBackedRandom(this)

public fun Random.asJavaRandom(): JavaRandom =
    if (this is JavaBackedRandom) this.delegate else KotlinBackedRandom(this)
