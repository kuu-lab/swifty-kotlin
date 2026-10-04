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
    val indexSource = OneShot(listOf(1, 2, 4, 3))
    println("index=${indexSource.indexOf(4)}")
    println("index-iterators=${indexSource.iteratorCalls}")

    val nullableSource = OneShot(listOf<String?>(null, "hit", null))
    println("nullable-index=${nullableSource.indexOf(null)}")

    var firstCalls = 0
    val firstSource = OneShot(listOf(1, 2, 4, 3))
    println("first=${firstSource.indexOfFirst {
        firstCalls += 1
        it % 2 == 0
    }}")
    println("first-calls=$firstCalls")

    var lastCalls = 0
    val lastSource = OneShot(listOf(1, 2, 4, 3))
    println("last=${lastSource.indexOfLast {
        lastCalls += 1
        it % 2 == 0
    }}")
    println("last-calls=$lastCalls")

    println("empty=${OneShot(emptyList<Int>()).indexOfFirst { true }}")
    println("missing=${OneShot(listOf(1, 3)).indexOfLast { it % 2 == 0 }}")
    println("list=${listOf(1, 2, 4).indexOfLast { it % 2 == 0 }}")

    var firstVisited = ""
    try {
        OneShot(listOf(1, 2, 3)).indexOfFirst {
            firstVisited += it.toString()
            if (it == 2) throw IllegalStateException("first predicate stop")
            false
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("first-visited=$firstVisited")

    var lastVisited = ""
    try {
        OneShot(listOf(1, 2, 3)).indexOfLast {
            lastVisited += it.toString()
            if (it == 2) throw IllegalStateException("last predicate stop")
            false
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("last-visited=$lastVisited")
}
