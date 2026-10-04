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

class ThrowingIterable : Iterable<Int> {
    override fun iterator(): Iterator<Int> {
        throw IllegalStateException("iterator stop")
    }
}

fun main() {
    // A statically Iterable List must still use the List fast path.
    val widenedList: Iterable<Int> = listOf(10, 20, 30)
    println(widenedList.elementAt(0))
    println(widenedList.elementAtOrNull(3))
    println(widenedList.elementAtOrElse(3) { index -> index * 100 })
    println(widenedList.elementAtOrElse(-1) { index -> index * 100 })

    // A non-List receiver is traversed once, in iterator order.
    val hit = OneShot(listOf(1, 2, 3))
    println(hit.elementAt(2))
    println(hit.iteratorCalls)

    val missing = OneShot(listOf(1, 2, 3))
    var defaultCalls = 0
    println(missing.elementAtOrElse(3) { index ->
        defaultCalls += 1
        index + 100
    })
    println(defaultCalls)
    println(missing.iteratorCalls)

    val tooLarge = OneShot(listOf(1, 2, 3))
    println(tooLarge.elementAtOrNull(99))
    println(tooLarge.iteratorCalls)

    val negative = OneShot(listOf(1, 2, 3))
    println(negative.elementAtOrElse(-7) { index -> index })
    println(negative.iteratorCalls)

    val nullable: Iterable<String?> = listOf(null, "value")
    println(nullable.elementAt(0) ?: "null-element")
    println(nullable.elementAtOrNull(1))

    val empty: Iterable<Int> = emptyList()
    println(empty.elementAtOrNull(0))
    try {
        empty.elementAt(0)
    } catch (e: IndexOutOfBoundsException) {
        println("empty elementAt: caught")
    }

    try {
        OneShot(listOf(1, 2, 3)).elementAt(3)
    } catch (e: IndexOutOfBoundsException) {
        println(e.message)
    }

    try {
        ThrowingIterable().elementAtOrElse(0) { 99 }
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    try {
        OneShot(listOf(1, 2, 3)).elementAtOrElse(3) {
            throw IllegalStateException("default stop")
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
