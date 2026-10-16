@file:OptIn(kotlin.ExperimentalUnsignedTypes::class, kotlin.test.ExperimentalKotlinTestApi::class)
@file:Suppress("DEPRECATION_ERROR")
import kotlin.test.*

fun main() {
    val iterable: Iterable<String>? = listOf("a", "b")
    assertContentEquals(iterable, listOf("a", "b"))
    assertContentEquals(null as Iterable<String>?, null)
    try { assertContentEquals(iterable, listOf("a", "c"), "Iterable-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(iterable, listOf("a"), "Iterable-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(listOf("a"), iterable, "Iterable-size-actual") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(iterable, null, "Iterable-null") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(null as Iterable<String>?, listOf("a", "b"), "Iterable-null-expected") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(iterable, listOf("a", "c")) { "Iterable-lazy" } } catch (e: AssertionError) { println(e.message) }

    val set: Set<String>? = linkedSetOf("a", "b")
    assertContentEquals(set, linkedSetOf("a", "b"))
    assertContentEquals(null as Set<String>?, null)
    try { assertContentEquals(set, linkedSetOf("a", "c"), "Set-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(set, linkedSetOf("a"), "Set-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(linkedSetOf("a"), set, "Set-size-actual") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(set, null, "Set-null") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(null as Set<String>?, linkedSetOf("a", "b"), "Set-null-expected") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(set, linkedSetOf("a", "c")) { "Set-lazy" } } catch (e: AssertionError) { println(e.message) }

    val sequence: Sequence<String>? = sequenceOf("a", "b")
    assertContentEquals(sequence, sequenceOf("a", "b"))
    assertContentEquals(null as Sequence<String>?, null)
    try { assertContentEquals(sequence, sequenceOf("a", "c"), "Sequence-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(sequence, sequenceOf("a"), "Sequence-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(sequenceOf("a"), sequence, "Sequence-size-actual") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(sequence, null, "Sequence-null") } catch (e: AssertionError) { println("Sequence-null:${e.message?.contains("Expected non-null Sequence <")}") }
    try { assertContentEquals(null as Sequence<String>?, sequenceOf("a", "b"), "Sequence-null-expected") } catch (e: AssertionError) { println("Sequence-null-expected:${e.message?.contains("Expected <null> Sequence, actual <")}") }
    try { assertContentEquals(sequence, sequenceOf("a", "c")) { "Sequence-lazy" } } catch (e: AssertionError) { println(e.message) }

    val aArray: Array<String?>? = arrayOf<String?>("a", null)
    assertContentEquals(aArray, arrayOf<String?>("a", null))
    assertContentEquals(null as Array<String?>?, null)
    try { assertContentEquals(aArray, arrayOf<String?>("a"), "Array-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aArray, arrayOf<String?>("b", null), "Array-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aArray, null, "Array-null") } catch (e: AssertionError) { println(e.message) }
    val aByteArray: ByteArray? = byteArrayOf(1.toByte(), 2.toByte())
    assertContentEquals(aByteArray, byteArrayOf(1.toByte(), 2.toByte()))
    assertContentEquals(null as ByteArray?, null)
    try { assertContentEquals(aByteArray, byteArrayOf(1.toByte()), "ByteArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aByteArray, byteArrayOf(3.toByte(), 2.toByte()), "ByteArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aByteArray, null, "ByteArray-null") } catch (e: AssertionError) { println(e.message) }
    val aShortArray: ShortArray? = shortArrayOf(1.toShort(), 2.toShort())
    assertContentEquals(aShortArray, shortArrayOf(1.toShort(), 2.toShort()))
    assertContentEquals(null as ShortArray?, null)
    try { assertContentEquals(aShortArray, shortArrayOf(1.toShort()), "ShortArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aShortArray, shortArrayOf(3.toShort(), 2.toShort()), "ShortArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aShortArray, null, "ShortArray-null") } catch (e: AssertionError) { println(e.message) }
    val aIntArray: IntArray? = intArrayOf(1, 2)
    assertContentEquals(aIntArray, intArrayOf(1, 2))
    assertContentEquals(null as IntArray?, null)
    try { assertContentEquals(aIntArray, intArrayOf(1), "IntArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aIntArray, intArrayOf(3, 2), "IntArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aIntArray, null, "IntArray-null") } catch (e: AssertionError) { println(e.message) }
    val aLongArray: LongArray? = longArrayOf(1L, 2L)
    assertContentEquals(aLongArray, longArrayOf(1L, 2L))
    assertContentEquals(null as LongArray?, null)
    try { assertContentEquals(aLongArray, longArrayOf(1L), "LongArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aLongArray, longArrayOf(3L, 2L), "LongArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aLongArray, null, "LongArray-null") } catch (e: AssertionError) { println(e.message) }
    val aBooleanArray: BooleanArray? = booleanArrayOf(true, false)
    assertContentEquals(aBooleanArray, booleanArrayOf(true, false))
    assertContentEquals(null as BooleanArray?, null)
    try { assertContentEquals(aBooleanArray, booleanArrayOf(true), "BooleanArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aBooleanArray, booleanArrayOf(false, false), "BooleanArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aBooleanArray, null, "BooleanArray-null") } catch (e: AssertionError) { println(e.message) }
    val aCharArray: CharArray? = charArrayOf('a', 'b')
    assertContentEquals(aCharArray, charArrayOf('a', 'b'))
    assertContentEquals(null as CharArray?, null)
    try { assertContentEquals(aCharArray, charArrayOf('a'), "CharArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aCharArray, charArrayOf('c', 'b'), "CharArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aCharArray, null, "CharArray-null") } catch (e: AssertionError) { println(e.message) }
    val aFloatArray: FloatArray? = floatArrayOf(1.0f, 2.0f)
    assertContentEquals(aFloatArray, floatArrayOf(1.0f, 2.0f))
    assertContentEquals(null as FloatArray?, null)
    try { assertContentEquals(aFloatArray, floatArrayOf(1.0f), "FloatArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aFloatArray, floatArrayOf(3.0f, 2.0f), "FloatArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aFloatArray, null, "FloatArray-null") } catch (e: AssertionError) { println(e.message) }
    val aDoubleArray: DoubleArray? = doubleArrayOf(1.0, 2.0)
    assertContentEquals(aDoubleArray, doubleArrayOf(1.0, 2.0))
    assertContentEquals(null as DoubleArray?, null)
    try { assertContentEquals(aDoubleArray, doubleArrayOf(1.0), "DoubleArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aDoubleArray, doubleArrayOf(3.0, 2.0), "DoubleArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aDoubleArray, null, "DoubleArray-null") } catch (e: AssertionError) { println(e.message) }
    val aUByteArray: UByteArray? = ubyteArrayOf(1u.toUByte(), 2u.toUByte())
    assertContentEquals(aUByteArray, ubyteArrayOf(1u.toUByte(), 2u.toUByte()))
    assertContentEquals(null as UByteArray?, null)
    try { assertContentEquals(aUByteArray, ubyteArrayOf(1u.toUByte()), "UByteArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aUByteArray, ubyteArrayOf(3u.toUByte(), 2u.toUByte()), "UByteArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aUByteArray, null, "UByteArray-null") } catch (e: AssertionError) { println(e.message) }
    val aUShortArray: UShortArray? = ushortArrayOf(1u.toUShort(), 2u.toUShort())
    assertContentEquals(aUShortArray, ushortArrayOf(1u.toUShort(), 2u.toUShort()))
    assertContentEquals(null as UShortArray?, null)
    try { assertContentEquals(aUShortArray, ushortArrayOf(1u.toUShort()), "UShortArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aUShortArray, ushortArrayOf(3u.toUShort(), 2u.toUShort()), "UShortArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aUShortArray, null, "UShortArray-null") } catch (e: AssertionError) { println(e.message) }
    val aUIntArray: UIntArray? = uintArrayOf(1u, 2u)
    assertContentEquals(aUIntArray, uintArrayOf(1u, 2u))
    assertContentEquals(null as UIntArray?, null)
    try { assertContentEquals(aUIntArray, uintArrayOf(1u), "UIntArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aUIntArray, uintArrayOf(3u, 2u), "UIntArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aUIntArray, null, "UIntArray-null") } catch (e: AssertionError) { println(e.message) }
    val aULongArray: ULongArray? = ulongArrayOf(1uL, 2uL)
    assertContentEquals(aULongArray, ulongArrayOf(1uL, 2uL))
    assertContentEquals(null as ULongArray?, null)
    try { assertContentEquals(aULongArray, ulongArrayOf(1uL), "ULongArray-size") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aULongArray, ulongArrayOf(3uL, 2uL), "ULongArray-element") } catch (e: AssertionError) { println(e.message) }
    try { assertContentEquals(aULongArray, null, "ULongArray-null") } catch (e: AssertionError) { println(e.message) }
    assertContentEquals(floatArrayOf(Float.NaN), floatArrayOf(Float.NaN))
    assertContentEquals(doubleArrayOf(Double.NaN), doubleArrayOf(Double.NaN))
    try { assertContentEquals(floatArrayOf(0.0f), floatArrayOf(-0.0f)) } catch (e: AssertionError) { println("float-zero:${e.message?.contains("elements differ")}") }
    try { assertContentEquals(doubleArrayOf(0.0), doubleArrayOf(-0.0)) } catch (e: AssertionError) { println("double-zero:${e.message?.contains("elements differ")}") }
}
