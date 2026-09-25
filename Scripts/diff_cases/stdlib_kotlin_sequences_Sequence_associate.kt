class ThrowingSequence : Sequence<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private var state = 0

        override fun hasNext(): Boolean = state < 2

        override fun next(): Int {
            if (state == 1) throw IllegalStateException("next failed")
            state += 1
            return 7
        }
    }
}

fun main() {
    // encounter order + last-write-wins on duplicate keys
    println(sequenceOf("a" to 1, "b" to 2, "a" to 3).associate { it })

    println(sequenceOf("a", "bb", "a").associateBy { it })
    println(sequenceOf("a", "bb", "a").associateBy({ it }, { it.length }))

    // supertype-keyed destinations exercise the `in` projections on M
    val byToDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val byToResult = sequenceOf("a", "bb").associateByTo(byToDestination) { it }
    println(byToResult === byToDestination)
    println(byToDestination)

    val byToTransformedDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val byToTransformedResult = sequenceOf("a", "bb").associateByTo(
        byToTransformedDestination,
        { it },
        { it.length }
    )
    println(byToTransformedResult === byToTransformedDestination)
    println(byToTransformedDestination)

    val toDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val toResult = sequenceOf("a", "bb").associateTo(toDestination) {
        Pair(it, it.length)
    }
    println(toResult === toDestination)
    println(toDestination)

    println(sequenceOf("a", "bb", "a").associateWith { it.length })

    val withToDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val withToResult = sequenceOf("a", "bb").associateWithTo(
        withToDestination
    ) { it.length }
    println(withToResult === withToDestination)
    println(withToDestination)

    println(emptySequence<String>().associate { it to it.length })

    var keyCalls = 0
    sequenceOf(1, 2, 3).associateBy {
        keyCalls += 1
        it
    }
    println(keyCalls)

    try {
        ThrowingSequence().associate { it to it }
        println("no-throw")
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
