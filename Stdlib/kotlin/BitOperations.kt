package kotlin

fun Int.countOneBits(): Int {
    var n = this
    var count = 0
    while (n != 0) {
        n = n and (n - 1)
        count++
    }
    return count
}

fun Int.countLeadingZeroBits(): Int {
    if (this == 0) return 32
    var n = this
    var count = 0
    if (n ushr 16 == 0) { count += 16; n = n shl 16 }
    if (n ushr 24 == 0) { count += 8; n = n shl 8 }
    if (n ushr 28 == 0) { count += 4; n = n shl 4 }
    if (n ushr 30 == 0) { count += 2; n = n shl 2 }
    if (n ushr 31 == 0) { count += 1 }
    return count
}

fun Int.countTrailingZeroBits(): Int {
    if (this == 0) return 32
    var n = this
    var count = 0
    if (n and 0xFFFF == 0) { count += 16; n = n ushr 16 }
    if (n and 0xFF == 0) { count += 8; n = n ushr 8 }
    if (n and 0xF == 0) { count += 4; n = n ushr 4 }
    if (n and 0x3 == 0) { count += 2; n = n ushr 2 }
    if (n and 0x1 == 0) { count += 1 }
    return count
}

fun Int.highestOneBit(): Int {
    var n = this
    n = n or (n ushr 1)
    n = n or (n ushr 2)
    n = n or (n ushr 4)
    n = n or (n ushr 8)
    n = n or (n ushr 16)
    return n - (n ushr 1)
}

fun Int.lowestOneBit(): Int = this and (-this)

fun Int.takeHighestOneBit(): Int = highestOneBit()

fun Int.takeLowestOneBit(): Int = lowestOneBit()

fun Int.rotateLeft(distance: Int): Int = (this shl distance) or (this ushr (32 - distance))

fun Int.rotateRight(distance: Int): Int = (this ushr distance) or (this shl (32 - distance))

fun Long.highestOneBit(): Long {
    var n = this
    n = n or (n ushr 1)
    n = n or (n ushr 2)
    n = n or (n ushr 4)
    n = n or (n ushr 8)
    n = n or (n ushr 16)
    n = n or (n ushr 32)
    return n - (n ushr 1)
}

fun Long.lowestOneBit(): Long = this and (-this)

fun Long.takeHighestOneBit(): Long = highestOneBit()

fun Long.takeLowestOneBit(): Long = lowestOneBit()

fun Long.rotateLeft(distance: Int): Long = (this shl distance) or (this ushr (64 - distance))

fun Long.rotateRight(distance: Int): Long = (this ushr distance) or (this shl (64 - distance))
