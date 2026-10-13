// KUU-1383: primitive-array getOrNull/elementAtOrElse/elementAt/single/singleOrNull/
// indexOfFirst/indexOfLast/toSet must resolve for every primitive array type.

fun main() {
    run {
        println("Int")
        val a = intArrayOf(3, 1, 2, 1)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { -1 })
        println(a.elementAtOrElse(9) { it })
        println(intArrayOf().elementAtOrElse(0) { -1 })
        println(intArrayOf(5).single())
        println(intArrayOf(5).singleOrNull())
        println(intArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 2 })
        println(a.singleOrNull { it == 2 })
        println(a.singleOrNull { it > 5 })
        println(a.singleOrNull { it == 1 })
        println(a.indexOfFirst { it == 2 })
        println(a.indexOfFirst { it == 9 })
        println(a.indexOfLast { it == 1 })
        println(a.indexOfLast { it == 9 })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { intArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 1 } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 9 } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Long")
        val a = longArrayOf(3L, 1L, 2L, 1L)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { -1L })
        println(a.elementAtOrElse(9) { it.toLong() })
        println(longArrayOf().elementAtOrElse(0) { -1L })
        println(longArrayOf(5L).single())
        println(longArrayOf(5L).singleOrNull())
        println(longArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 2L })
        println(a.singleOrNull { it == 2L })
        println(a.singleOrNull { it > 5L })
        println(a.singleOrNull { it == 1L })
        println(a.indexOfFirst { it == 2L })
        println(a.indexOfFirst { it == 9L })
        println(a.indexOfLast { it == 1L })
        println(a.indexOfLast { it == 9L })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { longArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 1L } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 9L } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Byte")
        val a = byteArrayOf(3, 1, 2, 1)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { (-1).toByte() })
        println(a.elementAtOrElse(9) { it.toByte() })
        println(byteArrayOf().elementAtOrElse(0) { (-1).toByte() })
        println(byteArrayOf(5).single())
        println(byteArrayOf(5).singleOrNull())
        println(byteArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() > 5 })
        println(a.singleOrNull { it.toInt() == 1 })
        println(a.indexOfFirst { it.toInt() == 2 })
        println(a.indexOfFirst { it.toInt() == 9 })
        println(a.indexOfLast { it.toInt() == 1 })
        println(a.indexOfLast { it.toInt() == 9 })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { byteArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it.toInt() == 1 } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it.toInt() == 9 } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Short")
        val a = shortArrayOf(3, 1, 2, 1)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { (-1).toShort() })
        println(a.elementAtOrElse(9) { it.toShort() })
        println(shortArrayOf().elementAtOrElse(0) { (-1).toShort() })
        println(shortArrayOf(5).single())
        println(shortArrayOf(5).singleOrNull())
        println(shortArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() > 5 })
        println(a.singleOrNull { it.toInt() == 1 })
        println(a.indexOfFirst { it.toInt() == 2 })
        println(a.indexOfFirst { it.toInt() == 9 })
        println(a.indexOfLast { it.toInt() == 1 })
        println(a.indexOfLast { it.toInt() == 9 })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { shortArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it.toInt() == 1 } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it.toInt() == 9 } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Char")
        val a = charArrayOf('c', 'a', 'b', 'a')
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { 'z' })
        println(a.elementAtOrElse(9) { 'q' })
        println(charArrayOf().elementAtOrElse(0) { 'z' })
        println(charArrayOf('e').single())
        println(charArrayOf('e').singleOrNull())
        println(charArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 'b' })
        println(a.singleOrNull { it == 'b' })
        println(a.singleOrNull { it == 'z' })
        println(a.singleOrNull { it == 'a' })
        println(a.indexOfFirst { it == 'b' })
        println(a.indexOfFirst { it == 'z' })
        println(a.indexOfLast { it == 'a' })
        println(a.indexOfLast { it == 'z' })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { charArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 'a' } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 'z' } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Boolean")
        val a = booleanArrayOf(true, false)
        println(a.elementAt(1))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(1) { true })
        println(a.elementAtOrElse(9) { it > 0 })
        println(booleanArrayOf().elementAtOrElse(0) { false })
        println(booleanArrayOf(true).single())
        println(booleanArrayOf(true).singleOrNull())
        println(booleanArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { !it })
        println(a.singleOrNull { !it })
        println(a.singleOrNull { it && false })
        println(booleanArrayOf(true, true).singleOrNull { it })
        println(a.indexOfFirst { !it })
        println(a.indexOfFirst { it && false })
        println(a.indexOfLast { it })
        println(a.indexOfLast { it && false })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { booleanArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { booleanArrayOf(true, true).single { it } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it && false } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Float")
        val a = floatArrayOf(3f, 1f, 2f, 1f)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { -1f })
        println(a.elementAtOrElse(9) { it.toFloat() })
        println(floatArrayOf().elementAtOrElse(0) { -1f })
        println(floatArrayOf(5f).single())
        println(floatArrayOf(5f).singleOrNull())
        println(floatArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 2f })
        println(a.singleOrNull { it == 2f })
        println(a.singleOrNull { it > 5f })
        println(a.singleOrNull { it == 1f })
        println(a.indexOfFirst { it == 2f })
        println(a.indexOfFirst { it == 9f })
        println(a.indexOfLast { it == 1f })
        println(a.indexOfLast { it == 9f })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { floatArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 1f } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 9f } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("Double")
        val a = doubleArrayOf(3.0, 1.0, 2.0, 1.0)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { -1.0 })
        println(a.elementAtOrElse(9) { it.toDouble() })
        println(doubleArrayOf().elementAtOrElse(0) { -1.0 })
        println(doubleArrayOf(5.0).single())
        println(doubleArrayOf(5.0).singleOrNull())
        println(doubleArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 2.0 })
        println(a.singleOrNull { it == 2.0 })
        println(a.singleOrNull { it > 5.0 })
        println(a.singleOrNull { it == 1.0 })
        println(a.indexOfFirst { it == 2.0 })
        println(a.indexOfFirst { it == 9.0 })
        println(a.indexOfLast { it == 1.0 })
        println(a.indexOfLast { it == 9.0 })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { doubleArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 1.0 } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 9.0 } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    unsignedBlocks()
}

@OptIn(ExperimentalUnsignedTypes::class)
fun unsignedBlocks() {
    run {
        println("UInt")
        val a = uintArrayOf(3u, 1u, 2u, 1u)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { 0u })
        println(a.elementAtOrElse(9) { it.toUInt() })
        println(uintArrayOf().elementAtOrElse(0) { 0u })
        println(uintArrayOf(5u).single())
        println(uintArrayOf(5u).singleOrNull())
        println(uintArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 2u })
        println(a.singleOrNull { it == 2u })
        println(a.singleOrNull { it > 5u })
        println(a.singleOrNull { it == 1u })
        println(a.indexOfFirst { it == 2u })
        println(a.indexOfFirst { it == 9u })
        println(a.indexOfLast { it == 1u })
        println(a.indexOfLast { it == 9u })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { uintArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 1u } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 9u } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("ULong")
        val a = ulongArrayOf(3uL, 1uL, 2uL, 1uL)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { 0uL })
        println(a.elementAtOrElse(9) { it.toULong() })
        println(ulongArrayOf().elementAtOrElse(0) { 0uL })
        println(ulongArrayOf(5uL).single())
        println(ulongArrayOf(5uL).singleOrNull())
        println(ulongArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it == 2uL })
        println(a.singleOrNull { it == 2uL })
        println(a.singleOrNull { it > 5uL })
        println(a.singleOrNull { it == 1uL })
        println(a.indexOfFirst { it == 2uL })
        println(a.indexOfFirst { it == 9uL })
        println(a.indexOfLast { it == 1uL })
        println(a.indexOfLast { it == 9uL })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { ulongArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it == 1uL } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it == 9uL } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("UByte")
        val a = ubyteArrayOf(3u, 1u, 2u, 1u)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { 9u.toUByte() })
        println(a.elementAtOrElse(9) { it.toUByte() })
        println(ubyteArrayOf().elementAtOrElse(0) { 9u.toUByte() })
        println(ubyteArrayOf(5u).single())
        println(ubyteArrayOf(5u).singleOrNull())
        println(ubyteArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() > 5 })
        println(a.singleOrNull { it.toInt() == 1 })
        println(a.indexOfFirst { it.toInt() == 2 })
        println(a.indexOfFirst { it.toInt() == 9 })
        println(a.indexOfLast { it.toInt() == 1 })
        println(a.indexOfLast { it.toInt() == 9 })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { ubyteArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it.toInt() == 1 } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it.toInt() == 9 } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
    run {
        println("UShort")
        val a = ushortArrayOf(3u, 1u, 2u, 1u)
        println(a.elementAt(2))
        println(a.getOrNull(1))
        println(a.getOrNull(9))
        println(a.getOrNull(-1))
        println(a.elementAtOrElse(2) { 9u.toUShort() })
        println(a.elementAtOrElse(9) { it.toUShort() })
        println(ushortArrayOf().elementAtOrElse(0) { 9u.toUShort() })
        println(ushortArrayOf(5u).single())
        println(ushortArrayOf(5u).singleOrNull())
        println(ushortArrayOf().singleOrNull())
        println(a.singleOrNull())
        println(a.single { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() == 2 })
        println(a.singleOrNull { it.toInt() > 5 })
        println(a.singleOrNull { it.toInt() == 1 })
        println(a.indexOfFirst { it.toInt() == 2 })
        println(a.indexOfFirst { it.toInt() == 9 })
        println(a.indexOfLast { it.toInt() == 1 })
        println(a.indexOfLast { it.toInt() == 9 })
        println(a.toSet())
        try { a.elementAt(9) } catch (e: ArrayIndexOutOfBoundsException) { println("elementAt-oob") }
        try { ushortArrayOf().single() } catch (e: NoSuchElementException) { println("NSEE:${e.message}") }
        try { a.single() } catch (e: IllegalArgumentException) { println("IAE:${e.message}") }
        try { a.single { it.toInt() == 1 } } catch (e: IllegalArgumentException) { println("IAE-p:${e.message}") }
        try { a.single { it.toInt() == 9 } } catch (e: NoSuchElementException) { println("NSEE-p:${e.message}") }
    }
}
