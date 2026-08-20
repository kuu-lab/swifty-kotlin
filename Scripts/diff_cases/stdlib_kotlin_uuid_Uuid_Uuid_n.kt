@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class, kotlin.ExperimentalUnsignedTypes::class)

import kotlin.uuid.Uuid

fun main() {
    val a = Uuid.fromLongs(0x0102030405060708L, 0x090A0B0C0D0E0F10L)
    val b = Uuid.fromLongs(0x0102030405060708L, 0x090A0B0C0D0E0F10L)
    val c = Uuid.fromLongs(0x1111111111111111L, 0x2222222222222222L)
    val nil = Uuid.fromLongs(0L, 0L)

    println(a.toString())
    println(a.toHexString())
    println(a.toHexDashString())
    println(a.toByteArray().joinToString(","))
    println(a.toUByteArray().joinToString(","))
    println(a.compareTo(b))
    println(a.compareTo(c))
    println(a == b)
    println(a == c)
    println(a.equals(b))
    println(a.equals("not a uuid"))
    println(a.equals(null))
    println(a.hashCode())
    println(b.hashCode())
    println(c.hashCode())
    println(nil.hashCode())
    println(a.toLongs { msb, lsb -> msb + lsb })
    println(a.toULongs { msb, lsb -> msb + lsb })
    println(hashSetOf(a, b, c).size)

    println("OK")
}
