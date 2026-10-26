package kotlin

// Long remains a Kotlin primitive while these companion extensions expose
// Java's wrapper static APIs through its primitive type name. Double's JVM
// static methods stay available through the java.lang.Double name only.
public val Long.Companion.SIZE: Int get() = java.lang.Long.SIZE

public val Long.Companion.BYTES: Int get() = java.lang.Long.BYTES

public fun Long.Companion.parseLong(value: String): Long = java.lang.Long.parseLong(value)

public fun Long.Companion.parseLong(value: String, radix: Int): Long =
    java.lang.Long.parseLong(value, radix)

public fun Long.Companion.parseUnsignedLong(value: String): Long =
    java.lang.Long.parseUnsignedLong(value)

public fun Long.Companion.parseUnsignedLong(value: String, radix: Int): Long =
    java.lang.Long.parseUnsignedLong(value, radix)

public fun Long.Companion.toString(value: Long): String = java.lang.Long.toString(value)

public fun Long.Companion.toString(value: Long, radix: Int): String =
    java.lang.Long.toString(value, radix)

public fun Long.Companion.toUnsignedString(value: Long): String =
    java.lang.Long.toUnsignedString(value)

public fun Long.Companion.toUnsignedString(value: Long, radix: Int): String =
    java.lang.Long.toUnsignedString(value, radix)

public fun Long.Companion.toHexString(value: Long): String = java.lang.Long.toHexString(value)

public fun Long.Companion.toOctalString(value: Long): String = java.lang.Long.toOctalString(value)

public fun Long.Companion.toBinaryString(value: Long): String = java.lang.Long.toBinaryString(value)

public fun Long.Companion.compare(first: Long, second: Long): Int =
    java.lang.Long.compare(first, second)

public fun Long.Companion.compareUnsigned(first: Long, second: Long): Int =
    java.lang.Long.compareUnsigned(first, second)

public fun Long.Companion.signum(value: Long): Int = java.lang.Long.signum(value)

public fun Long.Companion.highestOneBit(value: Long): Long = java.lang.Long.highestOneBit(value)

public fun Long.Companion.lowestOneBit(value: Long): Long = java.lang.Long.lowestOneBit(value)

public fun Long.Companion.numberOfLeadingZeros(value: Long): Int =
    java.lang.Long.numberOfLeadingZeros(value)

public fun Long.Companion.numberOfTrailingZeros(value: Long): Int =
    java.lang.Long.numberOfTrailingZeros(value)

public fun Long.Companion.bitCount(value: Long): Int = java.lang.Long.bitCount(value)

public fun Long.Companion.rotateLeft(value: Long, distance: Int): Long =
    java.lang.Long.rotateLeft(value, distance)

public fun Long.Companion.rotateRight(value: Long, distance: Int): Long =
    java.lang.Long.rotateRight(value, distance)

public fun Long.Companion.reverse(value: Long): Long = java.lang.Long.reverse(value)

public fun Long.Companion.reverseBytes(value: Long): Long = java.lang.Long.reverseBytes(value)

public fun Long.Companion.min(first: Long, second: Long): Long = java.lang.Long.min(first, second)

public fun Long.Companion.max(first: Long, second: Long): Long = java.lang.Long.max(first, second)

public fun Long.Companion.sum(first: Long, second: Long): Long = java.lang.Long.sum(first, second)

public val Double.Companion.MIN_NORMAL: Double get() = java.lang.Double.MIN_NORMAL

public val Double.Companion.MAX_EXPONENT: Int get() = java.lang.Double.MAX_EXPONENT

public val Double.Companion.MIN_EXPONENT: Int get() = java.lang.Double.MIN_EXPONENT

public val Double.Companion.SIZE: Int get() = java.lang.Double.SIZE

public val Double.Companion.BYTES: Int get() = java.lang.Double.BYTES
