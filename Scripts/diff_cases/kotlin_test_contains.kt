@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
import kotlin.test.*

class SearchItem(val label: String) {
    override fun equals(other: Any?): Boolean {
        println("equals:$label")
        return other is SearchItem
    }
    override fun hashCode(): Int = 0
}

fun main() {
    val closed: ClosedRange<Double> = 1.0..3.0
    val open: OpenEndRange<Int> = 1..<3
    assertContains(listOf<String?>("a", null), null)
    try { assertContains(listOf<String?>("a", null), "z", message = "iterable") } catch (e: AssertionError) { println("iterable:${e.message?.startsWith("iterable. Expected ")}") }
    assertContains(sequenceOf(1, 2), 2)
    try { assertContains(sequenceOf(1, 2), 3, message = "sequence") } catch (e: AssertionError) { println("sequence:${e.message?.startsWith("sequence. Expected ")}") }
    assertContains(arrayOf<String?>("a", null), null)
    try { assertContains(arrayOf<String?>("a", null), "z", message = "array") } catch (e: AssertionError) { println("array:${e.message?.startsWith("array. Expected ")}") }
    assertContains(byteArrayOf(1.toByte(), 2.toByte()), 2.toByte())
    try { assertContains(byteArrayOf(1.toByte(), 2.toByte()), 3.toByte(), message = "Byte") } catch (e: AssertionError) { println("Byte:${e.message?.startsWith("Byte. Expected ")}") }
    assertContains(shortArrayOf(1.toShort(), 2.toShort()), 2.toShort())
    try { assertContains(shortArrayOf(1.toShort(), 2.toShort()), 3.toShort(), message = "Short") } catch (e: AssertionError) { println("Short:${e.message?.startsWith("Short. Expected ")}") }
    assertContains(intArrayOf(1, 2), 2)
    try { assertContains(intArrayOf(1, 2), 3, message = "Int") } catch (e: AssertionError) { println("Int:${e.message?.startsWith("Int. Expected ")}") }
    assertContains(longArrayOf(1L, 2L), 2L)
    try { assertContains(longArrayOf(1L, 2L), 3L, message = "Long") } catch (e: AssertionError) { println("Long:${e.message?.startsWith("Long. Expected ")}") }
    assertContains(booleanArrayOf(false), false)
    try { assertContains(booleanArrayOf(false), true, message = "Boolean") } catch (e: AssertionError) { println("Boolean:${e.message?.startsWith("Boolean. Expected ")}") }
    assertContains(charArrayOf('a', 'b'), 'b')
    try { assertContains(charArrayOf('a', 'b'), 'c', message = "Char") } catch (e: AssertionError) { println("Char:${e.message?.startsWith("Char. Expected ")}") }
    assertContains(ubyteArrayOf(1u.toUByte(), 2u.toUByte()), 2u.toUByte())
    try { assertContains(ubyteArrayOf(1u.toUByte(), 2u.toUByte()), 3u.toUByte(), message = "UByte") } catch (e: AssertionError) { println("UByte:${e.message?.startsWith("UByte. Expected ")}") }
    assertContains(ushortArrayOf(1u.toUShort(), 2u.toUShort()), 2u.toUShort())
    try { assertContains(ushortArrayOf(1u.toUShort(), 2u.toUShort()), 3u.toUShort(), message = "UShort") } catch (e: AssertionError) { println("UShort:${e.message?.startsWith("UShort. Expected ")}") }
    assertContains(uintArrayOf(1u, 2u), 2u)
    try { assertContains(uintArrayOf(1u, 2u), 3u, message = "UInt") } catch (e: AssertionError) { println("UInt:${e.message?.startsWith("UInt. Expected ")}") }
    assertContains(ulongArrayOf(1uL, 2uL), 2uL)
    try { assertContains(ulongArrayOf(1uL, 2uL), 3uL, message = "ULong") } catch (e: AssertionError) { println("ULong:${e.message?.startsWith("ULong. Expected ")}") }
    assertContains(1..3, 2)
    try { assertContains(1..3, 4, message = "IntRange") } catch (e: AssertionError) { println("IntRange:${e.message?.startsWith("IntRange. Expected ")}") }
    assertContains(1L..3L, 2L)
    try { assertContains(1L..3L, 4L, message = "LongRange") } catch (e: AssertionError) { println("LongRange:${e.message?.startsWith("LongRange. Expected ")}") }
    assertContains('a'..'c', 'b')
    try { assertContains('a'..'c', 'z', message = "CharRange") } catch (e: AssertionError) { println("CharRange:${e.message?.startsWith("CharRange. Expected ")}") }
    assertContains(1u..3u, 2u)
    try { assertContains(1u..3u, 4u, message = "UIntRange") } catch (e: AssertionError) { println("UIntRange:${e.message?.startsWith("UIntRange. Expected ")}") }
    assertContains(1uL..3uL, 2uL)
    try { assertContains(1uL..3uL, 4uL, message = "ULongRange") } catch (e: AssertionError) { println("ULongRange:${e.message?.startsWith("ULongRange. Expected ")}") }
    assertContains(closed, 2.0)
    try { assertContains(closed, 4.0, message = "ClosedRange") } catch (e: AssertionError) { println("ClosedRange:${e.message?.startsWith("ClosedRange. Expected ")}") }
    assertContains(open, 2)
    try { assertContains(open, 3, message = "OpenEndRange") } catch (e: AssertionError) { println("OpenEndRange:${e.message?.startsWith("OpenEndRange. Expected ")}") }
    assertContains(mapOf<String?, Int>(null to 1, "a" to 2), null)
    try { assertContains(mapOf<String?, Int>(null to 1, "a" to 2), "z", message = "map") } catch (e: AssertionError) { println("map:${e.message?.startsWith("map. Expected ")}") }
    assertContains("Abc", 'b')
    try { assertContains("Abc", 'z', message = "char") } catch (e: AssertionError) { println("char:${e.message?.startsWith("char. Expected ")}") }
    assertContains("Abc", "bc")
    try { assertContains("Abc", "xy", message = "substring") } catch (e: AssertionError) { println("substring:${e.message?.startsWith("substring. Expected ")}") }
    assertContains("abc123", Regex("[0-9]+"))
    try { assertContains("abc123", Regex("XYZ"), message = "regex") } catch (e: AssertionError) { println("regex:${e.message?.startsWith("regex. Expected ")}") }
    assertContains("Abc", 'a', ignoreCase = true)
    assertContains("Abc", "AB", ignoreCase = true)
    var consumed = 0
    val once = sequence { for (i in 1..5) { consumed++; yield(i) } }
    assertContains(once, 3)
    println("consumed:$consumed")
    val item = SearchItem("item")
    val target = SearchItem("target")
    println("index:${sequenceOf(item).indexOf(target)}")
    assertContains(sequenceOf(item), target)
}
