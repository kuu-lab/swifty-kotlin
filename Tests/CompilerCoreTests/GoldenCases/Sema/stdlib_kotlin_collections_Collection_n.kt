@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package golden.sema

import kotlin.random.Random

fun collectionSurface(
    values: Collection<Int>,
    nullableValues: Collection<Int>?,
    booleans: Collection<Boolean>,
    bytes: Collection<Byte>,
    chars: Collection<Char>,
    doubles: Collection<Double>,
    floats: Collection<Float>,
    ints: Collection<Int>,
    longs: Collection<Long>,
    shorts: Collection<Short>,
    ubytes: Collection<UByte>,
    ushorts: Collection<UShort>,
    uints: Collection<UInt>,
    ulongs: Collection<ULong>
) {
    val containsAll = values.containsAll(listOf(1, 2))
    val count = values.count()
    val indices = values.indices
    val nullOrEmpty = nullableValues.isNullOrEmpty()
    val orEmpty = nullableValues.orEmpty()

    val plusElement = values + 3
    val plusIterable = values + listOf(3)
    val plusSequence = values + sequenceOf(3)
    val plusArray = values + arrayOf(3)
    val plusElementAlias = values.plusElement(3)

    val random = values.random()
    val randomSeeded = values.random(Random(7))
    val randomOrNull = values.randomOrNull()
    val randomOrNullSeeded = values.randomOrNull(Random(7))

    val mutable = values.toMutableList()
    val booleanArray = booleans.toBooleanArray()
    val byteArray = bytes.toByteArray()
    val charArray = chars.toCharArray()
    val doubleArray = doubles.toDoubleArray()
    val floatArray = floats.toFloatArray()
    val intArray = ints.toIntArray()
    val longArray = longs.toLongArray()
    val shortArray = shorts.toShortArray()
    val ubyteArray = ubytes.toUByteArray()
    val ushortArray = ushorts.toUShortArray()
    val uintArray = uints.toUIntArray()
    val ulongArray = ulongs.toULongArray()

    println(
        containsAll && count >= 0 && indices.first == 0 &&
            nullOrEmpty == (nullableValues == null || nullableValues.isEmpty()) &&
            orEmpty.isEmpty() == (nullableValues == null || nullableValues.isEmpty()) &&
            plusElement.size == plusIterable.size &&
            plusSequence.size == plusArray.size &&
            plusElementAlias.size == plusElement.size &&
            random != null && randomSeeded != null &&
            randomOrNull != null && randomOrNullSeeded != null &&
            mutable.size == values.size &&
            booleanArray.size == booleans.size && byteArray.size == bytes.size &&
            charArray.size == chars.size && doubleArray.size == doubles.size &&
            floatArray.size == floats.size && intArray.size == ints.size &&
            longArray.size == longs.size && shortArray.size == shorts.size &&
            ubyteArray.size == ubytes.size && ushortArray.size == ushorts.size &&
            uintArray.size == uints.size && ulongArray.size == ulongs.size
    )
}
