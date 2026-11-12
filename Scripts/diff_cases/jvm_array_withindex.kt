// DIFF_JVM
@file:OptIn(ExperimentalUnsignedTypes::class)

private fun <T> render(entries: Iterable<IndexedValue<T>>): String {
    val result = StringBuilder()
    for ((index, value) in entries) result.append("$index:$value ")
    return result.toString().trimEnd()
}

private fun <T> printDirect(array: Array<out T>) {
    for ((index, value) in array.withIndex()) println("$index:$value")
}

fun main() {
    val objects = arrayOf<String?>(null, "before")
    printDirect(objects)
    val indexedObjects: Iterable<IndexedValue<String?>> = objects.withIndex()
    objects[1] = "after"
    println(render(indexedObjects))

    val ints = intArrayOf(10, 20, 30)
    for ((index, value) in ints.withIndex()) println(index + value)
    val indexedInts: Iterable<IndexedValue<Int>> = ints.withIndex()
    val cursor = indexedInts.iterator()
    println(cursor.hasNext())
    ints[0] = 9
    val first = cursor.next()
    println("${first.index}:${first.value}")
    ints[1] = 8
    println(render(indexedInts))
    val second = cursor.next()
    println("${second.index}:${second.value}")

    println(render(byteArrayOf(-128, 127).withIndex()))
    println(render(shortArrayOf(-32768, 32767).withIndex()))
    println(render(longArrayOf(2147483648L, -1L).withIndex()))
    println(render(floatArrayOf(1.5f, -2.0f).withIndex()))
    println(render(doubleArrayOf(2.5, -3.0).withIndex()))
    println(render(booleanArrayOf(true, false).withIndex()))
    println(render(charArrayOf('a', 'z').withIndex()))

    for ((index, value) in uintArrayOf(4294967295u, 1u).withIndex()) println("$index:$value")
    for ((index, value) in ulongArrayOf(18446744073709551615uL).withIndex()) println("$index:$value")
    val uints = uintArrayOf(1u, 2u)
    val indexedUInts: Iterable<IndexedValue<UInt>> = uints.withIndex()
    uints[0] = 4294967295u
    println(render(indexedUInts))
    println(render(ulongArrayOf(18446744073709551615uL, 3uL).withIndex()))
    println(render(ubyteArrayOf(255u, 4u).withIndex()))
    println(render(ushortArrayOf(65535u, 5u).withIndex()))

    for ((index, value) in intArrayOf().withIndex()) println("unexpected $index:$value")
    println(emptyArray<String>().withIndex().iterator().hasNext())
    println(uintArrayOf().withIndex().iterator().hasNext())
    val empty = intArrayOf().withIndex().iterator()
    println(empty.hasNext())
    try {
        empty.next()
        println("unexpected element")
    } catch (e: NoSuchElementException) {
        println("exhausted")
    }
}
