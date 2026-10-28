// KUU-3661: toString() on nullable Float?/Double?/ULong? receivers must
// render "null" for real nulls — their null sentinel bit pattern coincides
// with a legitimate value (0.0/-0.0/ULong 2^63), so the tagged Any-member
// bridge needs a null check first. Real sentinel-colliding values must keep
// their actual digits, and every other primitive must be unaffected.
fun main() {
    val nullDouble: Double? = null
    val nullFloat: Float? = null
    val nullULong: ULong? = null
    val nullLong: Long? = null
    val nullInt: Int? = null
    val nullChar: Char? = null
    val nullBool: Boolean? = null
    println(nullDouble.toString())
    println(nullFloat.toString())
    println(nullULong.toString())
    println(nullLong.toString())
    println(nullInt.toString())
    println(nullChar.toString())
    println(nullBool.toString())

    val negZero: Double? = -0.0
    val negZeroF: Float? = -0.0f
    val ulongMax: ULong? = ULong.MAX_VALUE
    val ulongSentinel: ULong? = 9223372036854775808uL
    val longMin: Long? = Long.MIN_VALUE
    println(negZero.toString())
    println(negZeroF.toString())
    println(ulongMax.toString())
    println(ulongSentinel.toString())
    println(longMin.toString())

    // Non-null receivers must keep working through the same fallback path.
    println((-0.0).toString())
    println((-0.0f).toString())
    println(ULong.MAX_VALUE.toString())
    println(9223372036854775808uL.toString())
    println(Long.MIN_VALUE.toString())
    println(0.0.toString())
    println(1.5.toString())
}
