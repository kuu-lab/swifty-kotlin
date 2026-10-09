// DIFF_CANDIDATE_ONLY: Experimental lazy-message APIs are marked SinceKotlin("2.4"); the reference compiler targets Kotlin 2.3.10.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kotlin_test_families_lazy.expected
// Reference: JetBrains/kotlin revision 150f34458460c5d688ba80e13f269ca6715f32b4.
@file:OptIn(kotlin.ExperimentalUnsignedTypes::class, kotlin.test.ExperimentalKotlinTestApi::class)
import kotlin.test.*

fun main() {
    var messages = 0
    val closed: ClosedRange<Double> = 1.0..3.0
    val open: OpenEndRange<Int> = 1..<3
    assertContains(listOf<String?>("a", null), null) { messages++; "iterable" }
    try { assertContains(listOf<String?>("a", null), "z") { messages++; "iterable" } } catch (e: AssertionError) { println("iterable:${e.message?.startsWith("iterable. Expected ")}") }
    assertContains(sequenceOf(1, 2), 2) { messages++; "sequence" }
    try { assertContains(sequenceOf(1, 2), 3) { messages++; "sequence" } } catch (e: AssertionError) { println("sequence:${e.message?.startsWith("sequence. Expected ")}") }
    assertContains(arrayOf<String?>("a", null), null) { messages++; "array" }
    try { assertContains(arrayOf<String?>("a", null), "z") { messages++; "array" } } catch (e: AssertionError) { println("array:${e.message?.startsWith("array. Expected ")}") }
    assertContains(byteArrayOf(1.toByte(), 2.toByte()), 2.toByte()) { messages++; "Byte" }
    try { assertContains(byteArrayOf(1.toByte(), 2.toByte()), 3.toByte()) { messages++; "Byte" } } catch (e: AssertionError) { println("Byte:${e.message?.startsWith("Byte. Expected ")}") }
    assertContains(shortArrayOf(1.toShort(), 2.toShort()), 2.toShort()) { messages++; "Short" }
    try { assertContains(shortArrayOf(1.toShort(), 2.toShort()), 3.toShort()) { messages++; "Short" } } catch (e: AssertionError) { println("Short:${e.message?.startsWith("Short. Expected ")}") }
    assertContains(intArrayOf(1, 2), 2) { messages++; "Int" }
    try { assertContains(intArrayOf(1, 2), 3) { messages++; "Int" } } catch (e: AssertionError) { println("Int:${e.message?.startsWith("Int. Expected ")}") }
    assertContains(longArrayOf(1L, 2L), 2L) { messages++; "Long" }
    try { assertContains(longArrayOf(1L, 2L), 3L) { messages++; "Long" } } catch (e: AssertionError) { println("Long:${e.message?.startsWith("Long. Expected ")}") }
    assertContains(booleanArrayOf(false), false) { messages++; "Boolean" }
    try { assertContains(booleanArrayOf(false), true) { messages++; "Boolean" } } catch (e: AssertionError) { println("Boolean:${e.message?.startsWith("Boolean. Expected ")}") }
    assertContains(charArrayOf('a', 'b'), 'b') { messages++; "Char" }
    try { assertContains(charArrayOf('a', 'b'), 'c') { messages++; "Char" } } catch (e: AssertionError) { println("Char:${e.message?.startsWith("Char. Expected ")}") }
    assertContains(ubyteArrayOf(1u.toUByte(), 2u.toUByte()), 2u.toUByte()) { messages++; "UByte" }
    try { assertContains(ubyteArrayOf(1u.toUByte(), 2u.toUByte()), 3u.toUByte()) { messages++; "UByte" } } catch (e: AssertionError) { println("UByte:${e.message?.startsWith("UByte. Expected ")}") }
    assertContains(ushortArrayOf(1u.toUShort(), 2u.toUShort()), 2u.toUShort()) { messages++; "UShort" }
    try { assertContains(ushortArrayOf(1u.toUShort(), 2u.toUShort()), 3u.toUShort()) { messages++; "UShort" } } catch (e: AssertionError) { println("UShort:${e.message?.startsWith("UShort. Expected ")}") }
    assertContains(uintArrayOf(1u, 2u), 2u) { messages++; "UInt" }
    try { assertContains(uintArrayOf(1u, 2u), 3u) { messages++; "UInt" } } catch (e: AssertionError) { println("UInt:${e.message?.startsWith("UInt. Expected ")}") }
    assertContains(ulongArrayOf(1uL, 2uL), 2uL) { messages++; "ULong" }
    try { assertContains(ulongArrayOf(1uL, 2uL), 3uL) { messages++; "ULong" } } catch (e: AssertionError) { println("ULong:${e.message?.startsWith("ULong. Expected ")}") }
    assertContains(1..3, 2) { messages++; "IntRange" }
    try { assertContains(1..3, 4) { messages++; "IntRange" } } catch (e: AssertionError) { println("IntRange:${e.message?.startsWith("IntRange. Expected ")}") }
    assertContains(1L..3L, 2L) { messages++; "LongRange" }
    try { assertContains(1L..3L, 4L) { messages++; "LongRange" } } catch (e: AssertionError) { println("LongRange:${e.message?.startsWith("LongRange. Expected ")}") }
    assertContains('a'..'c', 'b') { messages++; "CharRange" }
    try { assertContains('a'..'c', 'z') { messages++; "CharRange" } } catch (e: AssertionError) { println("CharRange:${e.message?.startsWith("CharRange. Expected ")}") }
    assertContains(1u..3u, 2u) { messages++; "UIntRange" }
    try { assertContains(1u..3u, 4u) { messages++; "UIntRange" } } catch (e: AssertionError) { println("UIntRange:${e.message?.startsWith("UIntRange. Expected ")}") }
    assertContains(1uL..3uL, 2uL) { messages++; "ULongRange" }
    try { assertContains(1uL..3uL, 4uL) { messages++; "ULongRange" } } catch (e: AssertionError) { println("ULongRange:${e.message?.startsWith("ULongRange. Expected ")}") }
    assertContains(closed, 2.0) { messages++; "ClosedRange" }
    try { assertContains(closed, 4.0) { messages++; "ClosedRange" } } catch (e: AssertionError) { println("ClosedRange:${e.message?.startsWith("ClosedRange. Expected ")}") }
    assertContains(open, 2) { messages++; "OpenEndRange" }
    try { assertContains(open, 3) { messages++; "OpenEndRange" } } catch (e: AssertionError) { println("OpenEndRange:${e.message?.startsWith("OpenEndRange. Expected ")}") }
    assertContains(mapOf<String?, Int>(null to 1, "a" to 2), null) { messages++; "map" }
    try { assertContains(mapOf<String?, Int>(null to 1, "a" to 2), "z") { messages++; "map" } } catch (e: AssertionError) { println("map:${e.message?.startsWith("map. Expected ")}") }
    assertContains("Abc", 'b') { messages++; "char" }
    try { assertContains("Abc", 'z') { messages++; "char" } } catch (e: AssertionError) { println("char:${e.message?.startsWith("char. Expected ")}") }
    assertContains("Abc", "bc") { messages++; "substring" }
    try { assertContains("Abc", "xy") { messages++; "substring" } } catch (e: AssertionError) { println("substring:${e.message?.startsWith("substring. Expected ")}") }
    assertContains("abc123", Regex("[0-9]+")) { messages++; "regex" }
    try { assertContains("abc123", Regex("XYZ")) { messages++; "regex" } } catch (e: AssertionError) { println("regex:${e.message?.startsWith("regex. Expected ")}") }
    assertContentEquals(arrayOf<String?>("a", null), arrayOf<String?>("a", null)) { messages++; "Array" }
    try { assertContentEquals(arrayOf<String?>("a", null), arrayOf<String?>("b", null)) { messages++; "Array" } } catch (e: AssertionError) { println("Array:${e.message?.startsWith("Array. Array elements differ")}") }
    assertContentEquals(byteArrayOf(1.toByte(), 2.toByte()), byteArrayOf(1.toByte(), 2.toByte())) { messages++; "ByteArray" }
    try { assertContentEquals(byteArrayOf(1.toByte(), 2.toByte()), byteArrayOf(3.toByte(), 2.toByte())) { messages++; "ByteArray" } } catch (e: AssertionError) { println("ByteArray:${e.message?.startsWith("ByteArray. Array elements differ")}") }
    assertContentEquals(shortArrayOf(1.toShort(), 2.toShort()), shortArrayOf(1.toShort(), 2.toShort())) { messages++; "ShortArray" }
    try { assertContentEquals(shortArrayOf(1.toShort(), 2.toShort()), shortArrayOf(3.toShort(), 2.toShort())) { messages++; "ShortArray" } } catch (e: AssertionError) { println("ShortArray:${e.message?.startsWith("ShortArray. Array elements differ")}") }
    assertContentEquals(intArrayOf(1, 2), intArrayOf(1, 2)) { messages++; "IntArray" }
    try { assertContentEquals(intArrayOf(1, 2), intArrayOf(3, 2)) { messages++; "IntArray" } } catch (e: AssertionError) { println("IntArray:${e.message?.startsWith("IntArray. Array elements differ")}") }
    assertContentEquals(longArrayOf(1L, 2L), longArrayOf(1L, 2L)) { messages++; "LongArray" }
    try { assertContentEquals(longArrayOf(1L, 2L), longArrayOf(3L, 2L)) { messages++; "LongArray" } } catch (e: AssertionError) { println("LongArray:${e.message?.startsWith("LongArray. Array elements differ")}") }
    assertContentEquals(booleanArrayOf(true, false), booleanArrayOf(true, false)) { messages++; "BooleanArray" }
    try { assertContentEquals(booleanArrayOf(true, false), booleanArrayOf(false, false)) { messages++; "BooleanArray" } } catch (e: AssertionError) { println("BooleanArray:${e.message?.startsWith("BooleanArray. Array elements differ")}") }
    assertContentEquals(charArrayOf('a', 'b'), charArrayOf('a', 'b')) { messages++; "CharArray" }
    try { assertContentEquals(charArrayOf('a', 'b'), charArrayOf('c', 'b')) { messages++; "CharArray" } } catch (e: AssertionError) { println("CharArray:${e.message?.startsWith("CharArray. Array elements differ")}") }
    assertContentEquals(floatArrayOf(1.0f, 2.0f), floatArrayOf(1.0f, 2.0f)) { messages++; "FloatArray" }
    try { assertContentEquals(floatArrayOf(1.0f, 2.0f), floatArrayOf(3.0f, 2.0f)) { messages++; "FloatArray" } } catch (e: AssertionError) { println("FloatArray:${e.message?.startsWith("FloatArray. Array elements differ")}") }
    assertContentEquals(doubleArrayOf(1.0, 2.0), doubleArrayOf(1.0, 2.0)) { messages++; "DoubleArray" }
    try { assertContentEquals(doubleArrayOf(1.0, 2.0), doubleArrayOf(3.0, 2.0)) { messages++; "DoubleArray" } } catch (e: AssertionError) { println("DoubleArray:${e.message?.startsWith("DoubleArray. Array elements differ")}") }
    assertContentEquals(ubyteArrayOf(1u.toUByte(), 2u.toUByte()), ubyteArrayOf(1u.toUByte(), 2u.toUByte())) { messages++; "UByteArray" }
    try { assertContentEquals(ubyteArrayOf(1u.toUByte(), 2u.toUByte()), ubyteArrayOf(3u.toUByte(), 2u.toUByte())) { messages++; "UByteArray" } } catch (e: AssertionError) { println("UByteArray:${e.message?.startsWith("UByteArray. Array elements differ")}") }
    assertContentEquals(ushortArrayOf(1u.toUShort(), 2u.toUShort()), ushortArrayOf(1u.toUShort(), 2u.toUShort())) { messages++; "UShortArray" }
    try { assertContentEquals(ushortArrayOf(1u.toUShort(), 2u.toUShort()), ushortArrayOf(3u.toUShort(), 2u.toUShort())) { messages++; "UShortArray" } } catch (e: AssertionError) { println("UShortArray:${e.message?.startsWith("UShortArray. Array elements differ")}") }
    assertContentEquals(uintArrayOf(1u, 2u), uintArrayOf(1u, 2u)) { messages++; "UIntArray" }
    try { assertContentEquals(uintArrayOf(1u, 2u), uintArrayOf(3u, 2u)) { messages++; "UIntArray" } } catch (e: AssertionError) { println("UIntArray:${e.message?.startsWith("UIntArray. Array elements differ")}") }
    assertContentEquals(ulongArrayOf(1uL, 2uL), ulongArrayOf(1uL, 2uL)) { messages++; "ULongArray" }
    try { assertContentEquals(ulongArrayOf(1uL, 2uL), ulongArrayOf(3uL, 2uL)) { messages++; "ULongArray" } } catch (e: AssertionError) { println("ULongArray:${e.message?.startsWith("ULongArray. Array elements differ")}") }
    assertEquals(1.0, 1.125, 0.25) { messages++; "Double" }
    try { assertEquals(1.0, 1.5, 0.25) { messages++; "Double" } } catch (e: AssertionError) { println("Double-assertEquals:${e.message?.startsWith("Double. Expected <")}") }
    assertNotEquals(1.0, 1.5, 0.25) { messages++; "Double" }
    try { assertNotEquals(1.0, 1.125, 0.25) { messages++; "Double" } } catch (e: AssertionError) { println("Double-assertNotEquals:${e.message?.startsWith("Double. Expected <")}") }
    assertEquals(1.0f, 1.125f, 0.25f) { messages++; "Float" }
    try { assertEquals(1.0f, 1.5f, 0.25f) { messages++; "Float" } } catch (e: AssertionError) { println("Float-assertEquals:${e.message?.startsWith("Float. Expected <")}") }
    assertNotEquals(1.0f, 1.5f, 0.25f) { messages++; "Float" }
    try { assertNotEquals(1.0f, 1.125f, 0.25f) { messages++; "Float" } } catch (e: AssertionError) { println("Float-assertNotEquals:${e.message?.startsWith("Float. Expected <")}") }
    assertIs<String>("ok") { messages++; "is" }
    assertIsNot<Int>("ok") { messages++; "not" }
    try { assertIs<Int>("ok") { messages++; "is" } } catch (e: AssertionError) { println(e.message?.startsWith("is. Expected value")) }
    try { assertIsNot<String>("ok") { messages++; "not" } } catch (e: AssertionError) { println(e.message?.startsWith("not. Expected value")) }
    assertContentEquals(null as IntArray?, null) { messages++; "null" }
    try { assertContentEquals(null as IntArray?, intArrayOf(1)) { messages++; "null" } } catch (e: AssertionError) { println(e.message?.startsWith("null. Expected <null> Array")) }
    try { assertContentEquals(intArrayOf(1), intArrayOf(1, 2)) { messages++; "size" } } catch (e: AssertionError) { println(e.message?.startsWith("size. Array sizes differ")) }
    println("messages:$messages")
}
