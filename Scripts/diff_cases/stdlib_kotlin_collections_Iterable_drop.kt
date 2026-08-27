class OneShot<T>(private val values: List<T>) : Iterable<T> {
    private var used = false
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        if (used) throw IllegalStateException("iterator reused")
        used = true
        iteratorCalls += 1
        return values.iterator()
    }
}

fun main() {
    val dropSource = OneShot(listOf(1, 2, 3, 4))
    println(dropSource.drop(0))
    println(dropSource.iteratorCalls)

    val partialDropSource = OneShot(listOf(1, 2, 3, 4))
    println(partialDropSource.drop(2))
    println(partialDropSource.iteratorCalls)

    println(OneShot(listOf(1, 2, 3)).drop(3))
    println(OneShot(listOf(1, 2, 3)).drop(20))
    try {
        OneShot(listOf(1)).drop(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    var partialCalls = 0
    val partialDropWhileSource = OneShot(listOf(1, 2, 3, 1, 4))
    println(partialDropWhileSource.dropWhile {
        partialCalls += 1
        it < 3
    })
    println(partialCalls)
    println(OneShot(listOf(1, 2, 3)).dropWhile { it < 10 })
    println(OneShot(listOf(1, 2, 3)).dropWhile { it < 1 })
    println(emptyList<Int>().dropWhile { true })

    val nullable = OneShot(listOf(null, "kept", null))
    println(nullable.dropWhile { it == null })

    try {
        OneShot(listOf(1, 2, 3)).dropWhile {
            if (it == 2) throw IllegalStateException("predicate stop")
            true
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    println(listOf(1, 2, 3).drop(1))
    println(listOf(1, 2, 3).dropWhile { it < 2 })
}
