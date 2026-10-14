// KUU-2126: indexed array loops, primitive iterators, and existing text controls.
fun <T> indexedArray(xs: Array<out T>): String {
    val result = StringBuilder()
    for ((i, x) in xs.withIndex()) result.append("$i:$x;")
    return result.toString()
}

fun <T : CharSequence> indexedText(xs: T): String {
    val result = StringBuilder()
    for ((i, x) in xs.withIndex()) result.append("$i:$x;")
    return result.toString()
}

fun main() {
    println(indexedArray(arrayOf("a", "b")))
    println(indexedArray(arrayOf<String?>(null, "x")))
    for ((i, xs) in arrayOf(intArrayOf(3), intArrayOf(4)).withIndex()) {
        println("nested=$i:${xs[0]}")
    }
    for ((i, x) in intArrayOf(10, 20).withIndex()) println("int=$i:$x")
    for ((i, x) in longArrayOf(30L, 40L).withIndex()) println("long=$i:$x")
    for ((i, x) in byteArrayOf(-128, 127).withIndex()) {
        val index: Int = i
        val value: Byte = x
        println("byte=$index:$value")
    }
    val shorts: Any = shortArrayOf(-32768, 32767)
    if (shorts is ShortArray) {
        for ((i, x) in shorts.withIndex()) {
            val value: Short = x
            println("short=$i:$value")
        }
    }

    val bytes = byteArrayOf(1, 2, 3)
    val indexed = bytes.withIndex()
    bytes[0] = 9
    for (entry in indexed) println("entry=${entry.index}:${entry.value}")
    for ((_, x) in indexed) print("$x;")
    println()
    for ((i, _) in indexed) print("$i;")
    println()
    var count = 0
    for ((_, _) in indexed) count++
    println("count=$count")
    for ((i, x) in byteArrayOf(1, 2, 3, 4).withIndex()) {
        if (i == 1) continue
        if (i == 3) break
        println("control=$i:$x")
    }
    for ((i, x) in ByteArray(0).withIndex()) println("unexpected=$i:$x")
    for ((i, x) in ShortArray(0).withIndex()) println("unexpected=$i:$x")

    val byteIterator: ByteIterator = byteArrayOf(-1).iterator()
    println(byteIterator.nextByte())
    println(byteIterator.hasNext())
    try { byteIterator.nextByte() } catch (e: NoSuchElementException) { println("byte exhausted") }
    val shortIterator: ShortIterator = shortArrayOf(-2).iterator()
    println(shortIterator.nextShort())
    println(shortIterator.hasNext())
    try { shortIterator.next() } catch (e: NoSuchElementException) { println("short exhausted") }
    val indexedIterator = byteArrayOf(7).withIndex().iterator()
    println(indexedIterator.next().value)
    try { indexedIterator.next() } catch (e: NoSuchElementException) { println("indexed exhausted") }

    println(indexedText("ab"))
    val text: CharSequence = "cd"
    println(indexedText(text))
    println(indexedText(""))
    val mutableText = StringBuilder("ef")
    for ((i, x) in mutableText.withIndex()) {
        println("text=$i:$x")
        mutableText.setLength(0)
    }
}
