// KSP-963: Iterable.asIterable() must return the exact receiver without
// consuming or replacing its iterator.
class TrackedIterable : Iterable<Int> {
    var iteratorCalls = 0

    override fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        return listOf(1, 2, 3).iterator()
    }
}

fun <T> preservesIdentity(values: Iterable<T>): Boolean = values.asIterable() === values

fun main() {
    val list = listOf(1, 2, 3)
    val listResult = list.asIterable()
    println(listResult === list)
    println(listResult.toList())

    val nullableSet = setOf<String?>(null, "value")
    val setResult = nullableSet.asIterable()
    println(setResult === nullableSet)
    println(setResult.toList())

    val custom = TrackedIterable()
    val customResult = custom.asIterable()
    println(custom.iteratorCalls)
    println(customResult === custom)
    println(customResult.toList())
    println(custom.iteratorCalls)

    val inferred: Iterable<Int?> = listOf<Int?>(null, 7).asIterable()
    println(inferred.toList())
    println(preservesIdentity(list))
    println(preservesIdentity(nullableSet))
    println(preservesIdentity(custom))
}
