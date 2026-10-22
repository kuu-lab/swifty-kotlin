package kotlin

fun require(value: Boolean): Unit {
    if (!value) throw IllegalArgumentException("Failed requirement.")
}

fun require(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalArgumentException(lazyMessage().toString())
}

fun check(value: Boolean): Unit {
    if (!value) throw IllegalStateException("Check failed.")
}

fun check(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalStateException(lazyMessage().toString())
}

infix fun Int.and(other: Int): Int = this and other
infix fun Int.or(other: Int): Int = this or other
infix fun Int.shl(count: Int): Int = this shl count
infix fun Long.and(other: Long): Long = this and other
infix fun Long.or(other: Long): Long = this or other
infix fun Long.shl(count: Int): Long = this shl count
infix fun Byte.and(other: Int): Int = this.toInt() and other
infix fun Byte.and(other: Long): Long = this.toLong() and other

fun ByteArray.copyInto(destination: ByteArray, startIndex: Int, endIndex: Int): ByteArray {
    var index = startIndex
    while (index < endIndex) {
        destination[index - startIndex] = this[index]
        index += 1
    }
    return destination
}
