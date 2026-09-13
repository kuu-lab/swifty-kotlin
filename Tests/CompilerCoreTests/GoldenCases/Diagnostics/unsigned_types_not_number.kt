package golden.diagnostics

// BUG-251: UByte/UShort/UInt/ULong must not satisfy a `kotlin.Number` upper
// bound, and must not resolve `toChar()` (a member only `Number` declares).
// Real Kotlin deliberately keeps the unsigned integer types out of the
// `Number` hierarchy; this file locks in the corrected rejection for all
// four receivers so neither regresses independently.

fun ubyteToNumber(x: UByte): Number = x
fun ushortToNumber(x: UShort): Number = x
fun uintToNumber(x: UInt): Number = x
fun ulongToNumber(x: ULong): Number = x

fun ubyteToChar(x: UByte) = x.toChar()
fun ushortToChar(x: UShort) = x.toChar()
fun uintToChar(x: UInt) = x.toChar()
fun ulongToChar(x: ULong) = x.toChar()
