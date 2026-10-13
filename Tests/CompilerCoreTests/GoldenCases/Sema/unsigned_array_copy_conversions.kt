// KUU-1421: signed<->unsigned primitive array copy conversions
// (toUByteArray/toByteArray and siblings) resolve and return the converted
// array type on both primitive and boxed receivers.
@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package golden.sema

fun signedToUnsignedArrays(
    bytes: ByteArray,
    shorts: ShortArray,
    ints: IntArray,
    longs: LongArray
) {
    val ubyteArray = bytes.toUByteArray()
    val checkedUByte: UByteArray = ubyteArray
    val ushortArray = shorts.toUShortArray()
    val checkedUShort: UShortArray = ushortArray
    val uintArray = ints.toUIntArray()
    val checkedUInt: UIntArray = uintArray
    val ulongArray = longs.toULongArray()
    val checkedULong: ULongArray = ulongArray
}

fun unsignedToSignedArrays(
    ubytes: UByteArray,
    ushorts: UShortArray,
    uints: UIntArray,
    ulongs: ULongArray
) {
    val byteArray = ubytes.toByteArray()
    val checkedByte: ByteArray = byteArray
    val shortArray = ushorts.toShortArray()
    val checkedShort: ShortArray = shortArray
    val intArray = uints.toIntArray()
    val checkedInt: IntArray = intArray
    val longArray = ulongs.toLongArray()
    val checkedLong: LongArray = longArray
}

fun boxedUnsignedToPrimitiveArrays(
    ubytes: Array<out UByte>,
    ushorts: Array<out UShort>,
    uints: Array<out UInt>,
    ulongs: Array<out ULong>
) {
    val ubyteArray = ubytes.toUByteArray()
    val checkedUByte: UByteArray = ubyteArray
    val ushortArray = ushorts.toUShortArray()
    val checkedUShort: UShortArray = ushortArray
    val uintArray = uints.toUIntArray()
    val checkedUInt: UIntArray = uintArray
    val ulongArray = ulongs.toULongArray()
    val checkedULong: ULongArray = ulongArray
}

fun sameTypeUnsignedArrayCopies(
    ubytes: UByteArray,
    ushorts: UShortArray,
    uints: UIntArray,
    ulongs: ULongArray
) {
    val ubyteCopy = ubytes.toUByteArray()
    val checkedUByte: UByteArray = ubyteCopy
    val ushortCopy = ushorts.toUShortArray()
    val checkedUShort: UShortArray = ushortCopy
    val uintCopy = uints.toUIntArray()
    val checkedUInt: UIntArray = uintCopy
    val ulongCopy = ulongs.toULongArray()
    val checkedULong: ULongArray = ulongCopy
}
