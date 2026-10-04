// KSP-981: the last-family calls below use an Iterable-typed receiver so the
// generic source-backed implementations are exercised instead of List members.
class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        if (iteratorCalls > 1) throw IllegalStateException("iterator reused")
        return values.iterator()
    }
}

fun main() {
    val list: Iterable<Int> = listOf(1, 2, 2, 4)
    println("list.last=${list.last()}")
    println("list.lastPredicate=${list.last { it % 2 == 0 }}")
    println("list.lastIndexOf2=${list.lastIndexOf(2)}")
    println("list.lastIndexOf9=${list.lastIndexOf(9)}")
    println("list.lastOrNull=${list.lastOrNull()}")
    println("list.lastOrNullPredicate=${list.lastOrNull { it > 10 }}")

    val set: Iterable<String> = setOf("first", "last")
    println("set.last=${set.last()}")
    println("set.lastIndexOfLast=${set.lastIndexOf("last")}")

    val nullable: Iterable<String?> = listOf("x", null, "x", null)
    println("nullable.last=${nullable.last()}")
    println("nullable.lastIndexOfNull=${nullable.lastIndexOf(null)}")
    println("nullable.lastIndexOfX=${nullable.lastIndexOf("x")}")
    println("nullable.lastOrNullNull=${nullable.lastOrNull { it == null }}")

    val lastOneShot = OneShotIterable(listOf(3, 5, 7))
    println("oneShot.last=${lastOneShot.last()},iterators=${lastOneShot.iteratorCalls}")

    val predicateOneShot = OneShotIterable(listOf(1, 2, 3, 4))
    var predicateCalls = 0
    println("oneShot.lastPredicate=${predicateOneShot.last { predicateCalls += 1; it % 2 == 0 }}")
    println("oneShot.lastPredicateCalls=$predicateCalls,iterators=${predicateOneShot.iteratorCalls}")

    val indexOneShot = OneShotIterable(listOf(3, 5, 3))
    println("oneShot.lastIndexOf=${indexOneShot.lastIndexOf(3)},iterators=${indexOneShot.iteratorCalls}")

    val orNullOneShot = OneShotIterable(listOf(8, 9))
    println("oneShot.lastOrNull=${orNullOneShot.lastOrNull()},iterators=${orNullOneShot.iteratorCalls}")

    val orNullPredicateOneShot = OneShotIterable(listOf(1, 2, 4, 3))
    println("oneShot.lastOrNullPredicate=${orNullPredicateOneShot.lastOrNull { it % 2 == 0 }},iterators=${orNullPredicateOneShot.iteratorCalls}")

    val throwingOneShot = OneShotIterable(listOf(1, 2, 3, 4))
    var visitedBeforeThrow = 0
    try {
        throwingOneShot.last {
            visitedBeforeThrow += 1
            if (it == 3) throw IllegalStateException("predicate stop")
            true
        }
    } catch (e: IllegalStateException) {
        println("predicate.threw=$visitedBeforeThrow,iterators=${throwingOneShot.iteratorCalls}")
    }

    val empty: Iterable<Int> = emptyList()
    println("empty.lastOrNull=${empty.lastOrNull()}")
    try {
        empty.last()
    } catch (e: NoSuchElementException) {
        println("empty.last=NoSuchElementException")
    }
    try {
        empty.last { true }
    } catch (e: NoSuchElementException) {
        println("empty.lastPredicate=NoSuchElementException")
    }
}
