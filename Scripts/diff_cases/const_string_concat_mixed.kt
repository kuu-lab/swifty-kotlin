// DIFF_JVM
const val unsignedInt = 0x8fffffffU
const val unsignedByte = 0x8ffU
const val unsignedLong = 0xffff_ffff_ffffU

const val mixedUnsignedInt = "INT " + 0x8fffffffU
const val mixedUnsignedByte = "BYTE " + 0x8ffU
const val mixedUnsignedLong = "LONG " + 0xffff_ffff_ffffU
const val mixedUnsignedIntReference = "INT " + unsignedInt
const val mixedUnsignedByteReference = "BYTE " + unsignedByte
const val mixedUnsignedLongReference = "LONG " + unsignedLong

const val signedValue = 5
const val mixedSignedInt = "SIGNED " + 5
const val mixedSignedIntReference = "SIGNED " + signedValue

fun main() {
    println(mixedUnsignedInt)
    println(mixedUnsignedByte)
    println(mixedUnsignedLong)
    println(mixedUnsignedIntReference)
    println(mixedUnsignedByteReference)
    println(mixedUnsignedLongReference)
    println(mixedSignedInt)
    println(mixedSignedIntReference)

    val runtimeValue = 5u
    println("RUNTIME " + runtimeValue)
    println("STRING " + "PAIR")
}
