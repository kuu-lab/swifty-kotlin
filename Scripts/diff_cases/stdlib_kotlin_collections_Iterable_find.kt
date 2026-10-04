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
    var findCalls = 0
    val findSource = OneShot(listOf(1, 2, 4, 3))
    println(findSource.find {
        findCalls += 1
        it % 2 == 0
    })
    println("find-calls=$findCalls")
    println("find-iterators=${findSource.iteratorCalls}")

    var findLastCalls = 0
    val findLastSource = OneShot(listOf(1, 2, 4, 3))
    println(findLastSource.findLast {
        findLastCalls += 1
        it % 2 == 0
    })
    println("findLast-calls=$findLastCalls")
    println("findLast-iterators=${findLastSource.iteratorCalls}")

    println(OneShot(emptyList<Int>()).find { true })
    println(OneShot(listOf(1, 3)).findLast { it % 2 == 0 })

    var nullableFindCalls = 0
    val nullableFind = OneShot(listOf<String?>(null, "hit", null))
    println(nullableFind.find {
        nullableFindCalls += 1
        it == null
    })
    println("nullable-find-calls=$nullableFindCalls")

    var nullableFindLastCalls = 0
    val nullableFindLast = OneShot(listOf<String?>(null, "hit", null))
    println(nullableFindLast.findLast {
        nullableFindLastCalls += 1
        it == null
    })
    println("nullable-findLast-calls=$nullableFindLastCalls")

    var findVisited = ""
    try {
        OneShot(listOf(1, 2, 3)).find {
            findVisited += it.toString()
            if (it == 2) throw IllegalStateException("find predicate stop")
            false
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("find-visited=$findVisited")

    var findLastVisited = ""
    try {
        OneShot(listOf(1, 2, 3)).findLast {
            findLastVisited += it.toString()
            if (it == 2) throw IllegalStateException("findLast predicate stop")
            false
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("findLast-visited=$findLastVisited")
}
