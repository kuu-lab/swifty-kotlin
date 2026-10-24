// Widening and identity numeric conversions that have no runtime callee must
// lower on every call shape. The member-call and safe-call lowerings keep their
// own conversion tables, and these shapes used to fall out of one of them and
// link against a raw `toUShort` / `toShort` / `toUByte` symbol.
fun main() {
    val ub: UByte = 250u
    println(ub.toUShort())
    println(ub.let { it.toUShort() })
    println(listOf(ub).map { it.toUShort() })
    val boxed: Any = ub
    if (boxed is UByte) println(boxed.toUShort())

    val ubn: UByte? = ub
    println(ubn?.toUShort())
    println(ubn?.toUByte())
    val ubNull: UByte? = null
    println(ubNull?.toUShort())
    println(ubNull?.toUByte())

    val us: UShort? = 60000u
    println(us?.toUShort())
    val usNull: UShort? = null
    println(usNull?.toUShort())

    val b: Byte? = -5
    println(b?.toShort())
    val bNull: Byte? = null
    println(bNull?.toShort())

    val s: Short? = -300
    println(s?.toShort())
    val sNull: Short? = null
    println(sNull?.toShort())
}
