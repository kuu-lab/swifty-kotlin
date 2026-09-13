// KSP-1533 audit: ULong numeric conversions that remain compiler/runtime-owned
// (KSP-1531's (c) column: toByte/toDouble/toFloat/toInt/toShort/toUByte/
// toUShort) after kk_ulong_to_char was deleted as dead lowering code —
// ULong.toChar() has no Sema binding because Kotlin's unsigned types don't
// extend Number and never declared that member. These cases pin the
// neighboring switch arms in CallLowerer so the deletion has no side effect.
//
// ULong.toUInt() was a second KSP-1531 misclassification found via this same
// case: it was wired as a representation-preserving 64->64 copy (correct for
// Long<->ULong) instead of an actual 64->32 truncating mask, so any value
// with a nonzero high 32 bits (including ULong.MAX_VALUE) printed and
// compared as garbage. Fixed by routing to the existing kk_long_to_uint,
// which already truncates via UInt32(truncatingIfNeeded:).
fun main() {
    println(ULong.MAX_VALUE.toDouble())
    println(ULong.MAX_VALUE.toFloat())
    println(ULong.MAX_VALUE.toInt())
    println(ULong.MAX_VALUE.toShort())
    println(ULong.MAX_VALUE.toByte())
    println(ULong.MAX_VALUE.toUInt())
    println(ULong.MAX_VALUE.toUInt() == UInt.MAX_VALUE)
    println(4294967301uL.toUInt())
    println(ULong.MAX_VALUE.toUShort())
    println(ULong.MAX_VALUE.toUByte())
    println(123uL.toUShort())
    println(123uL.toUByte())
}
