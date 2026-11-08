package java.security

public class SecureRandom {
    private val delegate: kotlin.random.SecureRandom = kotlin.random.SecureRandom.getInstance()

    public constructor()

    public constructor(seed: ByteArray) {
        setSeed(seed)
    }

    public companion object {
        public fun getInstanceStrong(): SecureRandom = SecureRandom()

        public fun getInstance(algorithm: String): SecureRandom {
            when (algorithm) {
                "SHA1PRNG", "NativePRNG", "NativePRNGBlocking", "NativePRNGNonBlocking",
                "Windows-PRNG", "DRBG" -> return SecureRandom()
                else -> throw NoSuchAlgorithmException(algorithm)
            }
        }
    }

    public fun setSeed(seed: ByteArray) {
        var folded = 0
        for (b in seed) folded = folded * 31 + b.toInt()
        delegate.setSeed(folded)
    }

    public fun setSeed(seed: Long) {
        delegate.setSeed((seed xor (seed ushr 32)).toInt())
    }

    public fun generateSeed(size: Int): ByteArray = delegate.generateSeed(size)

    public fun nextBytes(array: ByteArray) {
        delegate.nextBytes(array)
    }

    public fun nextInt(): Int {
        val bytes = ByteArray(4)
        nextBytes(bytes)
        return ((bytes[0].toInt() and 0xFF) shl 24) or
            ((bytes[1].toInt() and 0xFF) shl 16) or
            ((bytes[2].toInt() and 0xFF) shl 8) or
            (bytes[3].toInt() and 0xFF)
    }

    public fun nextInt(bound: Int): Int {
        if (bound <= 0) throw IllegalArgumentException("bound must be positive")
        var bits: Int
        var value: Int
        do {
            bits = nextInt() ushr 1
            value = bits % bound
        } while (bits - value + (bound - 1) < 0)
        return value
    }

    public fun nextLong(): Long {
        val bytes = ByteArray(8)
        nextBytes(bytes)
        var result = 0L
        for (b in bytes) result = (result shl 8) or (b.toLong() and 0xFF)
        return result
    }

    public fun nextBoolean(): Boolean = nextBits(1) != 0

    public fun nextFloat(): Float = nextBits(24).toFloat() / 16777216.0f

    public fun nextDouble(): Double =
        ((nextBits(26).toLong() shl 27) + nextBits(27).toLong()) / 9007199254740992.0

    private fun nextBits(count: Int): Int = nextInt() ushr (32 - count)
}
