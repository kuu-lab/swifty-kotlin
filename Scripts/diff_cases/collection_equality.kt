@file:OptIn(ExperimentalStdlibApi::class, ExperimentalUnsignedTypes::class)

private fun verify(value: Boolean, caseName: String) {
    check(value) { caseName }
}

private data class Record(val name: String, val group: Int)

private class Parity(private val value: Int) {
    override fun equals(other: Any?): Boolean = other is Parity && value % 2 == other.value % 2

    override fun hashCode(): Int = value % 2
}

private class TracedSequence(
    private val values: IntArray,
    private val trace: StringBuilder
) : Sequence<Int> {
    override fun iterator(): Iterator<Int> {
        trace.append("iterator;")
        return object : Iterator<Int> {
            private var index = 0

            override fun hasNext(): Boolean = index < values.size

            override fun next(): Int {
                val value = values[index++]
                trace.append("next$value;")
                return value
            }
        }
    }
}

private fun checkPrimitiveAndUnsignedOverloads() {
    val bytes = byteArrayOf(-128, -126)
    verify(!bytes.allEqual() && bytes.allDistinct(), "ByteArray values")
    verify(bytes.allEqualBy { it.toInt() % 2 } && bytes.allDistinctBy { it.toInt() }, "ByteArray keys")
    val shorts = shortArrayOf(-32768, -32766)
    verify(!shorts.allEqual() && shorts.allDistinct(), "ShortArray values")
    verify(shorts.allEqualBy { it.toInt() % 2 } && shorts.allDistinctBy { it.toInt() }, "ShortArray keys")
    val ints = intArrayOf(1, 3)
    verify(!ints.allEqual() && ints.allDistinct(), "IntArray values")
    verify(ints.allEqualBy { it % 2 } && ints.allDistinctBy { it }, "IntArray keys")
    val longs = longArrayOf(Long.MIN_VALUE, 0L)
    verify(!longs.allEqual() && longs.allDistinct(), "LongArray values")
    verify(longs.allEqualBy { it % 2L } && longs.allDistinctBy { it }, "LongArray keys")
    val floats = floatArrayOf(1f, 2f)
    verify(!floats.allEqual() && floats.allDistinct(), "FloatArray values")
    verify(!floats.allEqualBy { it.toInt() } && floats.allDistinctBy { it }, "FloatArray keys")
    val doubles = doubleArrayOf(1.0, 2.0)
    verify(!doubles.allEqual() && doubles.allDistinct(), "DoubleArray values")
    verify(!doubles.allEqualBy { it.toInt() } && doubles.allDistinctBy { it }, "DoubleArray keys")
    val booleans = booleanArrayOf(false, true)
    verify(!booleans.allEqual() && booleans.allDistinct(), "BooleanArray values")
    verify(!booleans.allEqualBy { it } && booleans.allDistinctBy { it }, "BooleanArray keys")
    verify(!booleanArrayOf(true, false, true).allDistinct(), "BooleanArray pigeonhole")
    val chars = charArrayOf('a', 'c')
    verify(!chars.allEqual() && chars.allDistinct(), "CharArray values")
    verify(chars.allEqualBy { it.code % 2 } && chars.allDistinctBy { it }, "CharArray keys")
    val ubytes = ubyteArrayOf(253u, 255u)
    verify(!ubytes.allEqual() && ubytes.allDistinct(), "UByteArray values")
    verify(ubytes.allEqualBy { it.toInt() % 2 } && ubytes.allDistinctBy { it }, "UByteArray keys")
    val ushorts = ushortArrayOf(65533u, 65535u)
    verify(!ushorts.allEqual() && ushorts.allDistinct(), "UShortArray values")
    verify(ushorts.allEqualBy { it.toInt() % 2 } && ushorts.allDistinctBy { it }, "UShortArray keys")
    val uints = uintArrayOf(UInt.MAX_VALUE, 1u)
    verify(!uints.allEqual() && uints.allDistinct(), "UIntArray values")
    verify(uints.allEqualBy { it % 2u } && uints.allDistinctBy { it }, "UIntArray keys")
    val ulongs = ulongArrayOf(9223372036854775808uL, 0uL)
    verify(!ulongs.allEqual() && ulongs.allDistinct(), "ULongArray values")
    verify(ulongs.allEqualBy { it % 2uL } && ulongs.allDistinctBy { it }, "ULongArray keys")
}

private fun checkNullableAndStructuralEquality() {
    val projected: Array<out String?> = arrayOf(null, null)
    verify(projected.allEqual() && !projected.allDistinct(), "null array elements")
    verify(projected.allEqualBy { it } && !projected.allDistinctBy { it }, "null array keys")
    val mixed: Iterable<Long?> = listOf(null, Long.MIN_VALUE)
    verify(!mixed.allEqual() && mixed.allDistinct(), "null and Long.MIN_VALUE")
    verify(!mixed.allEqualBy { it } && mixed.allDistinctBy { it }, "nullable keys")

    val records = listOf(Record("same", 1), Record("same", 1))
    verify(records.allEqual() && !records.allDistinct(), "data class equality")
    val parity = arrayOf(Parity(1), Parity(3))
    verify(parity.allEqual() && !parity.allDistinct(), "custom equals and hashCode")
    val groups = sequenceOf(Record("a", 1), Record("b", 1))
    verify(!groups.allEqual() && groups.allDistinct(), "sequence values")
    verify(groups.allEqualBy { listOf(it.group) } && !groups.allDistinctBy { listOf(it.group) }, "structural keys")
    verify(arrayOf(intArrayOf(1), intArrayOf(1)).allDistinct(), "array element identity")
}

private fun checkFloatingPointEquality() {
    val firstDoubleNaN = Double.fromBits(0x7ff8000000000001L)
    val secondDoubleNaN = Double.fromBits(0x7ff8000000000002L)
    val doubleNaNs = doubleArrayOf(firstDoubleNaN, secondDoubleNaN)
    verify(doubleNaNs.allEqual() && !doubleNaNs.allDistinct(), "DoubleArray NaNs")
    val doubleZeros = doubleArrayOf(-0.0, 0.0)
    verify(!doubleZeros.allEqual() && doubleZeros.allDistinct(), "DoubleArray signed zeros")

    val keys = HashSet<Double?>()
    verify(keys.add(null) && keys.add(-0.0) && keys.add(0.0), "HashSet null and signed zeros")
    verify(keys.add(firstDoubleNaN) && !keys.add(secondDoubleNaN), "HashSet NaN payloads")
    val firstFloatNaN = Float.fromBits(0x7fc00001)
    val secondFloatNaN = Float.fromBits(0x7fc00002)
    val floatNaNs = floatArrayOf(firstFloatNaN, secondFloatNaN)
    verify(floatNaNs.allEqual() && !floatNaNs.allDistinct(), "FloatArray NaNs")
    val floatZeros = floatArrayOf(-0.0f, 0.0f)
    verify(!floatZeros.allEqual() && floatZeros.allDistinct(), "FloatArray signed zeros")

    val boxedNaNs = arrayOf(firstDoubleNaN, secondDoubleNaN)
    verify(boxedNaNs.allEqual() && !boxedNaNs.allDistinct(), "boxed NaNs")
    val boxedZeros = sequenceOf(-0.0f, 0.0f)
    verify(!boxedZeros.allEqual() && boxedZeros.allDistinct(), "boxed signed zeros")
    verify(intArrayOf(0, 1).allEqualBy { doubleNaNs[it] }, "selector NaNs are equal")
    verify(!intArrayOf(0, 1).allDistinctBy { doubleNaNs[it] }, "selector NaNs are duplicates")
    verify(!listOf(0, 1).allEqualBy { floatZeros[it] }, "selector signed zeros differ")
    verify(listOf(0, 1).allDistinctBy { floatZeros[it] }, "selector signed zeros are distinct")
}

private fun returnFromSelector(): String {
    arrayOf(1, 2).allEqualBy { return "OK" }
    return "selector not called"
}

private fun checkSelectorEvaluation() {
    verify(emptyList<Int>().allEqual() && emptyList<Int>().allDistinct(), "empty iterable")
    verify(sequenceOf(1).allEqual() && sequenceOf(1).allDistinct(), "singleton sequence")
    var calls = 0
    verify(emptyList<Int>().allDistinctBy { ++calls }, "empty iterable selector")
    verify(sequenceOf(1).allEqualBy { ++calls }, "singleton sequence selector")
    verify(emptyArray<Int>().allEqualBy { ++calls }, "empty object array selector")
    verify(intArrayOf(1).allDistinctBy { ++calls }, "singleton primitive array selector")
    verify(ulongArrayOf(1uL).allEqualBy { ++calls }, "singleton unsigned array selector")
    verify(calls == 0, "no selector calls for fewer than two elements")

    val equalTrace = StringBuilder()
    val equality = TracedSequence(intArrayOf(1, 3, 2, 4), equalTrace).allEqualBy {
        equalTrace.append("key$it;")
        it % 2
    }
    verify(!equality, "first different key")
    verify(equalTrace.toString() == "iterator;next1;key1;next3;key3;next2;key2;", "equality iteration order")

    val distinctTrace = StringBuilder()
    val distinctness = TracedSequence(intArrayOf(1, 2, 3, 4), distinctTrace).allDistinctBy {
        distinctTrace.append("key$it;")
        it % 2
    }
    verify(!distinctness, "first duplicate key")
    verify(distinctTrace.toString() == "iterator;next1;key1;next2;key2;next3;key3;", "distinct iteration order")

    val array = intArrayOf(1, 2, 3)
    val seen = StringBuilder()
    verify(!array.allDistinctBy {
        seen.append(it)
        array[1] = 1
        it
    }, "array reads the next element after selector")
    verify(seen.toString() == "11", "array stops at the first duplicate")
    verify(returnFromSelector() == "OK", "non-local return from inline selector")
}

fun main() {
    verify(listOf(1, 2).allDistinct(), "list of distinct elements")
    verify(!sequenceOf("a", "b").allDistinctBy { it.length }, "sequence of duplicate keys")
    verify(arrayOf(3, 3).allEqual(), "array of equal elements")
    checkPrimitiveAndUnsignedOverloads()
    checkNullableAndStructuralEquality()
    checkFloatingPointEquality()
    checkSelectorEvaluation()
    println("OK")
}
