// KUU-4078: deprecated sumBy on Array<out T> and primitive/unsigned arrays.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    println(arrayOf(1, 2, 3).sumBy { it * it })
    println(arrayOf("a", "bb").sumBy { it.length })
    println(emptyArray<Int>().sumBy { it * 2 })

    println(byteArrayOf(1, 2).sumBy { it.toInt() * 2 })
    println(shortArrayOf(1, 2).sumBy { it.toInt() + 1 })
    println(intArrayOf(1, 2, 3).sumBy { -it })
    println(longArrayOf(1L, 2L).sumBy { it.toInt() })
    println(floatArrayOf(1.5f, 2.5f).sumBy { it.toInt() })
    println(doubleArrayOf(0.5, 2.5).sumBy { it.toInt() })
    println(booleanArrayOf(true, false, true).sumBy { if (it) 2 else 0 })
    println(charArrayOf('a', 'b').sumBy { it.code - 96 })

    println(ubyteArrayOf(1.toUByte(), 2.toUByte()).sumBy { it.toUInt() + 10u })
    println(ushortArrayOf(1.toUShort(), 2.toUShort()).sumBy { it.toUInt() })
    println(uintArrayOf(1u, 2u).sumBy { it * 3u })
    println(ulongArrayOf(1uL, 2uL).sumBy { it.toUInt() })
}
