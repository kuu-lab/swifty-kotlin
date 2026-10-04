@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

import kotlin.random.Random

fun main() {
    val values: Collection<Int> = listOf(1, 2, 2)
    val empty: Collection<Int> = emptyList()
    val nullable: Collection<Int>? = null
    val nonNull: Collection<Int>? = values

    println(values.containsAll(listOf(1, 2)))
    println(values.containsAll(listOf(1, 3)))
    println(values.count())
    println(values.indices)
    println(empty.indices)
    println(nullable.isNullOrEmpty())
    println(empty.isNullOrEmpty())
    println(values.isNullOrEmpty())
    println(nullable.orEmpty().isEmpty())
    println(nonNull.orEmpty() === values)

    println(values + 4)
    println(values + listOf(4, 5))
    println(values + sequenceOf(4, 5))
    println(values + arrayOf(4, 5))
    println(values.plusElement(4))

    val random1 = Random(7)
    val random2 = Random(7)
    println(values.random(random1) == values.random(random2))
    println(values.random() in values)
    println(values.randomOrNull(random1) in values)
    println(values.randomOrNull() in values)
    println(empty.randomOrNull() == null)
    try {
        empty.random(Random(1))
        println(false)
    } catch (_: NoSuchElementException) {
        println(true)
    }

    val mutable = values.toMutableList()
    mutable.add(9)
    println(values.size == 3 && mutable == listOf(1, 2, 2, 9))

    val booleanValues: Collection<Boolean> = listOf(true, false)
    val byteValues: Collection<Byte> = listOf((-1).toByte(), 2.toByte())
    val charValues: Collection<Char> = listOf('a', 'z')
    val doubleValues: Collection<Double> = listOf(-1.5, 2.5)
    val floatValues: Collection<Float> = listOf(-1.5f, 2.5f)
    val intValues: Collection<Int> = listOf(Int.MIN_VALUE, Int.MAX_VALUE)
    val longValues: Collection<Long> = listOf(Long.MIN_VALUE, Long.MAX_VALUE)
    val shortValues: Collection<Short> = listOf((-32768).toShort(), 32767.toShort())
    val ubyteValues: Collection<UByte> = listOf(0u.toUByte(), UByte.MAX_VALUE)
    val ushortValues: Collection<UShort> = listOf(0u.toUShort(), UShort.MAX_VALUE)
    val uintValues: Collection<UInt> = listOf(0u, UInt.MAX_VALUE)
    val ulongValues: Collection<ULong> = listOf(0uL, ULong.MAX_VALUE)

    println(booleanValues.toBooleanArray().contentToString())
    println(byteValues.toByteArray().contentToString())
    println(charValues.toCharArray().contentToString())
    println(doubleValues.toDoubleArray().contentToString())
    println(floatValues.toFloatArray().contentToString())
    println(intValues.toIntArray().contentToString())
    println(longValues.toLongArray().contentToString())
    println(shortValues.toShortArray().contentToString())
    println(ubyteValues.toUByteArray().contentToString())
    println(ushortValues.toUShortArray().contentToString())
    println(uintValues.toUIntArray().contentToString())
    println(ulongValues.toULongArray().contentToString())
}
