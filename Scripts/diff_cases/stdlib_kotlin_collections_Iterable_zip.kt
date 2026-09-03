private class OneShotIterator(
    private val values: Array<Int>,
    private val cursor: Array<Int>
) : Iterator<Int> {
    override fun hasNext(): Boolean = cursor[0] < values.size

    override fun next(): Int {
        if (!hasNext()) throw NoSuchElementException()
        val value = values[cursor[0]]
        cursor[0] = cursor[0] + 1
        return value
    }
}

private class OneShotIterable(
    private val values: Array<Int>,
    private val cursor: Array<Int>,
    private val iteratorCalls: Array<Int>
) : Iterable<Int> {
    override fun iterator(): Iterator<Int> {
        if (iteratorCalls[0] != 0) throw IllegalStateException("iterator called twice")
        iteratorCalls[0] = iteratorCalls[0] + 1
        return OneShotIterator(values, cursor)
    }
}

fun main() {
    val emptyPairCursor = arrayOf(0)
    val emptyPairIteratorCalls = arrayOf(0)
    val emptyPairSource = OneShotIterable(arrayOf(10, 11), emptyPairCursor, emptyPairIteratorCalls)
    println(emptyPairSource.zip(emptyArray<String>()))
    println("empty-pair:${emptyPairCursor[0]}:${emptyPairIteratorCalls[0]}")

    val emptyTransformCursor = arrayOf(0)
    val emptyTransformIteratorCalls = arrayOf(0)
    var emptyTransformCalls = 0
    val emptyTransformSource = OneShotIterable(arrayOf(12, 13), emptyTransformCursor, emptyTransformIteratorCalls)
    println(emptyTransformSource.zip(emptyArray<String>()) { left, right ->
        emptyTransformCalls = emptyTransformCalls + 1
        "$left$right"
    })
    println("empty-transform:${emptyTransformCursor[0]}:${emptyTransformIteratorCalls[0]}:$emptyTransformCalls")

    val shortCursor = arrayOf(0)
    val shortIteratorCalls = arrayOf(0)
    val shortSource = OneShotIterable(arrayOf(14), shortCursor, shortIteratorCalls)
    println(shortSource.zip(arrayOf("s", "t")))
    println("short:${shortCursor[0]}:${shortIteratorCalls[0]}")

    val pairCursor = arrayOf(0)
    val pairIteratorCalls = arrayOf(0)
    val pairSource = OneShotIterable(arrayOf(1, 2, 3, 99), pairCursor, pairIteratorCalls)
    println(pairSource.zip(arrayOf<String?>("a", null)))
    println("pair:${pairCursor[0]}:${pairIteratorCalls[0]}")

    val transformCursor = arrayOf(0)
    val transformIteratorCalls = arrayOf(0)
    var transformCalls = 0
    val transformSource = OneShotIterable(arrayOf(4, 5, 6, 99), transformCursor, transformIteratorCalls)
    val transformed = transformSource.zip(arrayOf("x", "y")) { left, right ->
        transformCalls = transformCalls + 1
        "$left$right"
    }
    println(transformed)
    println("transform:${transformCursor[0]}:${transformIteratorCalls[0]}:$transformCalls")

    val exceptionCursor = arrayOf(0)
    val exceptionIteratorCalls = arrayOf(0)
    var exceptionCalls = 0
    try {
        OneShotIterable(arrayOf(7, 8, 9), exceptionCursor, exceptionIteratorCalls)
            .zip(arrayOf("p", "q", "r")) { left, right ->
                exceptionCalls = exceptionCalls + 1
                if (left == 8) throw IllegalStateException("stop")
                "$left$right"
            }
    } catch (e: IllegalStateException) {
        println("exception:${exceptionCursor[0]}:${exceptionIteratorCalls[0]}:$exceptionCalls")
    }
}
