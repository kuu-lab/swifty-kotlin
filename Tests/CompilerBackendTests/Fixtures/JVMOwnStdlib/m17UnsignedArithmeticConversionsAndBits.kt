fun main() {
    val u = UInt.MAX_VALUE; val w = ULong.MAX_VALUE
    println(u); println(w); println(UByte.MAX_VALUE); println(UShort.MAX_VALUE)
    println(u + 1u); println(w + 1uL); println(u / 2u); println(u % 7u)
    println(w / 2uL); println(w % 7uL); println(u > 1u); println(w > 1uL)
    println(u.toLong()); println(u.toULong()); println((-1).toByte().toUInt()); println((-1).toLong().toULong())
    val b = 255u.toUByte(); val s = 65535u.toUShort()
    println(b.toInt()); println(s.toLong()); println(b + b); println(s * s)
    var n = b; n++; println(n); n--; println(n)
    println(u shr 1); println(w shr 63); println(1u shl 31); println(1uL shl 63)
    println(u and 255u); println(255u xor 15u); println(0u.inv())
    println((-1.0).toUInt()); println((0.0 / 0.0).toULong()); println((1.0 / 0.0).toUInt())
    println((1.0 / 0.0).toULong()); println(4294967296.0.toUInt()); println(42.9.toULong())
    println(u.toDouble()); println(w.toDouble()); println(b.hashCode()); println(s.hashCode())
    println(b.compareTo(1u.toUByte())); println(u.compareTo(1u)); println(w.compareTo(1uL))
    for (i in 4294967294u..4294967295u) { println(i) }
}
