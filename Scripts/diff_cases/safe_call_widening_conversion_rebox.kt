// A representation-preserving conversion through a safe call must produce a
// value of the *result* type, not keep the receiver's box.
fun main() {
    val ul: ULong? = 18000000000000000000uL
    val l: Long? = ul?.toLong()
    println(l)
    println(ul?.toLong())
    val anyL: Any? = ul?.toLong()
    println(anyL is Long)
    println(anyL is ULong)

    val b: Byte? = -5
    val i: Int? = b?.toInt()
    println(i)
    val anyI: Any? = b?.toInt()
    println(anyI is Int)
    println(anyI is Byte)
    val anyL2: Any? = b?.toLong()
    println(anyL2 is Long)
    println(anyL2 == -5L)

    val s: Short? = -300
    val anyS: Any? = s?.toInt()
    println(anyS is Int)
    println(anyS is Short)
    val anyS2: Any? = s?.toLong()
    println(anyS2 is Long)

    val b2: Byte? = 7
    val anyB: Any? = b2?.toShort()
    println(anyB is Short)
    println(anyB is Byte)

    val none: ULong? = null
    println(none?.toLong())
}
