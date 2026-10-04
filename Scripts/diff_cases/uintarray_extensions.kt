@OptIn(ExperimentalUnsignedTypes::class)
fun firstLarge(a: UIntArray): Int {
    a.forEachIndexed { i, v -> if (v > 3u) return i }
    return -1
}

@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val a = uintArrayOf(1u, 2u, 3u)
    println(a.toUIntArray().toList())
    println(intArrayOf(1, 2).toUIntArray().toList())
    println(arrayOf(1u, 2u).toUIntArray().toList())
    println(listOf(1u, 2u).toUIntArray().toList())
    println(a.indices)
    println(a.lastIndex)
    println(a.sum())
    println(a.maxOrNull())
    println(a.minOrNull())
    println(a.sorted().toList())
    println(a.elementAt(1))
    println(a.indexOf(3u))
    a.forEachIndexed { i, v -> print("$i$v") }
    println()
    println(a.sumOf { it })

    val high = uintArrayOf(4294967295u, 1u, 2147483648u, 0u, 1u)
    println(high.maxOrNull())
    println(high.minOrNull())
    val sorted = high.sorted()
    println(sorted)
    println(high.toList())
    high[0] = 2u
    println(sorted)
    println(high.indexOf(1u))
    println(high.indexOf(123u))
    println(firstLarge(high))
    println(uintArrayOf(4294967295u, 1u).sum())
    println(uintArrayOf(4294967295u, 1u).sumOf { it })
    println(uintArrayOf(4294967295u).maxOrNull())
    println(uintArrayOf(4294967295u).minOrNull())

    val copy = a.toUIntArray()
    a[0] = 9u
    copy[1] = 8u
    println(a.toList())
    println(copy.toList())
    val ints = intArrayOf(-1, -2147483648, 0, 2147483647)
    val converted = ints.toUIntArray()
    ints[0] = 0
    converted[1] = 1u
    println(ints.toList())
    println(converted.toList())
    val boxed: Array<out UInt> = arrayOf(4294967295u, 2147483648u)
    println(boxed.toUIntArray().toList())
    val objects = arrayOf(1u, 2u)
    val objectCopy = objects.toUIntArray()
    objects[0] = 9u
    objectCopy[1] = 8u
    println(objects.toList())
    println(objectCopy.toList())
    val collection: Collection<UInt> = linkedSetOf(3u, 4294967295u, 1u)
    println(collection.toUIntArray().toList())
    val list = mutableListOf(1u, 2u)
    val listCopy = list.toUIntArray()
    list[0] = 9u
    listCopy[1] = 8u
    println(list)
    println(listCopy.toList())

    val small = uintArrayOf(1u, 2u, 3u)
    println(small.sumOf { it.toDouble() + 0.5 })
    println(small.sumOf { it.toInt() })
    println(small.sumOf { it.toLong() })
    println(small.sumOf { it.toULong() })
    var calls = 0
    println(small.sumOf { calls++; it })
    println(calls)
    small.forEachIndexed { i, v -> small[i] = v + i.toUInt() }
    println(small.toList())

    val empty = uintArrayOf()
    println(empty.indices)
    println(empty.lastIndex)
    println(empty.sum())
    println(empty.maxOrNull())
    println(empty.minOrNull())
    println(empty.sorted())
    println(empty.indexOf(0u))
    println(empty.toUIntArray().toList())
    println(intArrayOf().toUIntArray().toList())
    println(arrayOf<UInt>().toUIntArray().toList())
    val emptyCollection: Collection<UInt> = emptyList<UInt>()
    println(emptyCollection.toUIntArray().toList())
    println(empty.sumOf { it.toDouble() })
    println(empty.sumOf { it.toInt() })
    println(empty.sumOf { it.toLong() })
    println(empty.sumOf { it })
    println(empty.sumOf { it.toULong() })
    empty.forEachIndexed { i, v -> println("unexpected:$i:$v") }
    println(firstLarge(empty))
    try {
        a.elementAt(-1)
        println("unexpected element")
    } catch (e: IndexOutOfBoundsException) {
        println("negative index")
    }
    try {
        a.elementAt(a.size)
        println("unexpected element")
    } catch (e: IndexOutOfBoundsException) {
        println("past end")
    }
    try {
        empty.elementAt(0)
        println("unexpected element")
    } catch (e: IndexOutOfBoundsException) {
        println("empty index")
    }
    try {
        a.sumOf { if (it == 9u) throw IllegalStateException("selector"); it }
        println("unexpected sum")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    try {
        a.forEachIndexed { i, v -> throw IllegalStateException("action:$i:$v") }
        println("unexpected action")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
