package golden.sema

// KUU-3967: a `u`-suffixed integer literal retargets to the unsigned type the
// call-site expected type demands. `ULong.and`/`or`/`xor` (and `shl`/`shr`)
// only declare a same-type parameter, so `x and 0xFFU` resolves only when the
// literal is re-inferred as ULong instead of eagerly staying UInt. A UInt
// *variable* in the same position is still an argument type mismatch — the
// retarget applies to literals only.

fun bignumMask(x: ULong, it: Int): ULong = (x shr (56 - (it * 8))) and 0xFFU
fun explicitCall(x: ULong): ULong = x.and(0xFFU)

fun main() {
    val x: ULong = 0x1234UL
    val a = x and 0xFFU
    val b = x or 0x0FU
    val c = x xor 0b1010U
    val d = x and 255U
    val ub: UByte = 0xABu
    val us: UShort = 0xFF00u
    val e = ub and 0x0FU
    val f = us or 0x0F00U
    val g = x shl 3
    val h = x shr 3
    val i: ULong = 0xFFU
    val j: UByte = 0xFFU
    val k: UShort = 0xFFU
    println("$a $b $c $d $e $f $g $h $i $j $k")
    println(bignumMask(x, 6))
    println(explicitCall(x))
}
