// KUU-1392: random/randomOrNull on Array<out T>, primitive arrays, and
// unsigned arrays — with and without a Random argument.
package golden.sema

import kotlin.random.Random

fun arrayRandom(values: Array<Int>, seeded: Random) {
    val randomOrNull = values.randomOrNull()
    val checkedOrNull: Int? = randomOrNull
    val randomOrNullSeeded = values.randomOrNull(seeded)
    val checkedOrNullSeeded: Int? = randomOrNullSeeded
}

fun primitiveArrayRandom(seeded: Random) {
    val intArray = intArrayOf(1, 2)
    val a1: Int = intArray.random()
    val a2: Int = intArray.random(seeded)
    val a3: Int? = intArray.randomOrNull()
    val a4: Int? = intArray.randomOrNull(seeded)
    val longArray = longArrayOf(1L, 2L)
    val b1: Long = longArray.random()
    val b2: Long = longArray.random(seeded)
    val b3: Long? = longArray.randomOrNull()
    val b4: Long? = longArray.randomOrNull(seeded)
    val byteArray = byteArrayOf(1, 2)
    val c1: Byte = byteArray.random()
    val c2: Byte = byteArray.random(seeded)
    val c3: Byte? = byteArray.randomOrNull()
    val c4: Byte? = byteArray.randomOrNull(seeded)
    val shortArray = shortArrayOf(1, 2)
    val d1: Short = shortArray.random()
    val d2: Short = shortArray.random(seeded)
    val d3: Short? = shortArray.randomOrNull()
    val d4: Short? = shortArray.randomOrNull(seeded)
    val charArray = charArrayOf('a', 'b')
    val e1: Char = charArray.random()
    val e2: Char = charArray.random(seeded)
    val e3: Char? = charArray.randomOrNull()
    val e4: Char? = charArray.randomOrNull(seeded)
    val booleanArray = booleanArrayOf(true, false)
    val f1: Boolean = booleanArray.random()
    val f2: Boolean = booleanArray.random(seeded)
    val f3: Boolean? = booleanArray.randomOrNull()
    val f4: Boolean? = booleanArray.randomOrNull(seeded)
    val floatArray = floatArrayOf(1.0f, 2.0f)
    val g1: Float = floatArray.random()
    val g2: Float = floatArray.random(seeded)
    val g3: Float? = floatArray.randomOrNull()
    val g4: Float? = floatArray.randomOrNull(seeded)
    val doubleArray = doubleArrayOf(1.0, 2.0)
    val h1: Double = doubleArray.random()
    val h2: Double = doubleArray.random(seeded)
    val h3: Double? = doubleArray.randomOrNull()
    val h4: Double? = doubleArray.randomOrNull(seeded)
}

@OptIn(ExperimentalUnsignedTypes::class)
fun unsignedArrayRandom(seeded: Random) {
    val uIntArray = uintArrayOf(1u, 2u)
    val i1: UInt = uIntArray.random()
    val i2: UInt = uIntArray.random(seeded)
    val i3: UInt? = uIntArray.randomOrNull()
    val i4: UInt? = uIntArray.randomOrNull(seeded)
    val uLongArray = ulongArrayOf(1uL, 2uL)
    val j1: ULong = uLongArray.random()
    val j2: ULong = uLongArray.random(seeded)
    val j3: ULong? = uLongArray.randomOrNull()
    val j4: ULong? = uLongArray.randomOrNull(seeded)
    val uByteArray = ubyteArrayOf(1u, 2u)
    val k1: UByte = uByteArray.random()
    val k2: UByte = uByteArray.random(seeded)
    val k3: UByte? = uByteArray.randomOrNull()
    val k4: UByte? = uByteArray.randomOrNull(seeded)
    val uShortArray = ushortArrayOf(1u, 2u)
    val l1: UShort = uShortArray.random()
    val l2: UShort = uShortArray.random(seeded)
    val l3: UShort? = uShortArray.randomOrNull()
    val l4: UShort? = uShortArray.randomOrNull(seeded)
}
