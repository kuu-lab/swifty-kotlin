private class TracedIterable(private val size: Int) : Iterable<Int> {
    var iteratorCalls = 0
    var nextCalls = 0

    override fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        val source = this
        return object : Iterator<Int> {
            private var index = 0

            override fun hasNext(): Boolean = index < source.size

            override fun next(): Int {
                source.nextCalls += 1
                val value = index + 10
                index += 1
                return value
            }
        }
    }
}

private class OneShotIterable(private val values: List<Int>) : Iterable<Int> {
    private var used = false

    override fun iterator(): Iterator<Int> {
        if (used) throw IllegalStateException("one-shot")
        used = true
        return values.iterator()
    }
}

private class ThrowingIterable : Iterable<Int> {
    override fun iterator(): Iterator<Int> {
        throw IllegalStateException("iterator failure")
    }
}

fun main() {
    val source = TracedIterable(3)
    val indexed: Iterable<IndexedValue<Int>> = source.withIndex()
    println("created=${source.iteratorCalls}:${source.nextCalls}")

    val iterator = indexed.iterator()
    println("iterator=${source.iteratorCalls}:${source.nextCalls}")
    println("first=${iterator.next()}")
    println("partial=${source.iteratorCalls}:${source.nextCalls}")
    println("second=${iterator.next()}")
    println("tail=${source.iteratorCalls}:${source.nextCalls}")

    println("repeat=${indexed.toList()}")
    println("repeatCalls=${source.iteratorCalls}:${source.nextCalls}")
    println("isList=${indexed is List<*>}")

    val list: List<Int> = listOf(7, 8)
    val listAsIterable: Iterable<IndexedValue<Int>> = list.withIndex()
    println("list=${listAsIterable.toList()}")

    val nullable: Iterable<Int?> = listOf(null, 4)
    for (entry in nullable.withIndex()) {
        println("nullable=${entry.index}:${entry.value}")
    }

    val objectIterable = object : Iterable<Int> {
        override fun iterator(): Iterator<Int> = listOf(5, 6).iterator()
    }
    println("object=${objectIterable.withIndex().toList()}")
    println("empty=${emptyList<Int>().withIndex().toList()}")

    val oneShot = OneShotIterable(listOf(9, 10)).withIndex()
    println("oneShot=${oneShot.toList()}")
    try {
        oneShot.toList()
        println("oneShot=not-thrown")
    } catch (error: IllegalStateException) {
        println("oneShot=${error.message}")
    }

    val throwing = ThrowingIterable().withIndex()
    println("throwing=created")
    try {
        throwing.iterator()
        println("throwing=not-thrown")
    } catch (error: IllegalStateException) {
        println("throwing=${error.message}")
    }
}
