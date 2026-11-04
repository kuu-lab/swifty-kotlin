// KUU-4078: deprecated sumByDouble on Array<out T> and primitive/unsigned arrays.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    println(arrayOf(1, 2, 3).sumByDouble { it * 0.5 })
    println(arrayOf("a", "bb").sumByDouble { it.length.toDouble() })
    println(emptyArray<Int>().sumByDouble { it.toDouble() })

    println(byteArrayOf(1, 2).sumByDouble { it.toDouble() })
    println(shortArrayOf(1, 2).sumByDouble { it.toDouble() + 0.25 })
    println(intArrayOf(1, 2, 3).sumByDouble { -it.toDouble() })
    println(longArrayOf(1L, 2L).sumByDouble { it.toDouble() })
    println(floatArrayOf(1.5f, 2.5f).sumByDouble { it.toDouble() })
    println(doubleArrayOf(0.5, 2.5).sumByDouble { it })
    println(booleanArrayOf(true, false).sumByDouble { if (it) 1.5 else 0.0 })
    println(charArrayOf('a', 'b').sumByDouble { (it.code - 96).toDouble() })

    println(ubyteArrayOf(1.toUByte(), 2.toUByte()).sumByDouble { it.toDouble() })
    println(ushortArrayOf(1.toUShort(), 2.toUShort()).sumByDouble { it.toDouble() })
    println(uintArrayOf(1u, 2u).sumByDouble { it.toDouble() })
    println(ulongArrayOf(1uL, 2uL).sumByDouble { it.toDouble() })
}
