package kotlin.random

public abstract class Random {
    public abstract fun nextBits(bitCount: Int): Int
    public open fun nextInt(): Int = 0
    public open fun nextInt(until: Int): Int = 0
    public open fun nextInt(from: Int, until: Int): Int = 0
    public open fun nextLong(): Long = 0L
    public open fun nextLong(until: Long): Long = 0L
    public open fun nextLong(from: Long, until: Long): Long = 0L
    public open fun nextBoolean(): Boolean = false
    public open fun nextDouble(): Double = 0.0
    public open fun nextDouble(until: Double): Double = 0.0
    public open fun nextDouble(from: Double, until: Double): Double = 0.0
    public open fun nextFloat(): Float = 0.0f
    public open fun nextBytes(array: ByteArray, fromIndex: Int = 0, toIndex: Int = array.size): ByteArray = null!!
    public open fun nextBytes(array: ByteArray): ByteArray = null!!
    public open fun nextBytes(size: Int): ByteArray = null!!

    public companion object Default : Random() {
        override fun nextBits(bitCount: Int): Int = 0
        override fun nextInt(): Int = 0
        override fun nextInt(until: Int): Int = 0
        override fun nextInt(from: Int, until: Int): Int = 0
        override fun nextLong(): Long = 0L
        override fun nextLong(until: Long): Long = 0L
        override fun nextLong(from: Long, until: Long): Long = 0L
        override fun nextBoolean(): Boolean = false
        override fun nextDouble(): Double = 0.0
        override fun nextDouble(until: Double): Double = 0.0
        override fun nextDouble(from: Double, until: Double): Double = 0.0
        override fun nextFloat(): Float = 0.0f
        override fun nextBytes(array: ByteArray, fromIndex: Int, toIndex: Int): ByteArray = null!!
        override fun nextBytes(array: ByteArray): ByteArray = null!!
        override fun nextBytes(size: Int): ByteArray = null!!
    }
}

public fun Random(seed: Int): Random = null!!
public fun Random(seed: Long): Random = null!!
