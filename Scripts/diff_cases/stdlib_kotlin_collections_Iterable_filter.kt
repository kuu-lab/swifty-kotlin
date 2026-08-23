class Counter(val limit: Int) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = CounterIterator(limit)
}

class CounterIterator(val limit: Int) : Iterator<Int> {
    var index = 0
    override fun hasNext(): Boolean = index < limit
    override fun next(): Int {
        val value = index
        index++
        return value
    }
}

class OneShot(val values: List<Int>) : Iterable<Int> {
    var consumed = false
    override fun iterator(): Iterator<Int> {
        check(!consumed) { "one-shot iterable reused" }
        consumed = true
        return values.iterator()
    }
}

open class Parent(val label: String)
class Child : Parent("child")

fun main() {
    val values: Iterable<Any?> = listOf(1, "two", null, 3, "four")
    println(values.filterIndexed { index, _ -> index % 2 == 0 })

    val indexedDestination = mutableListOf<Any?>("seed")
    val indexedResult = values.filterIndexedTo(indexedDestination) { index, _ -> index % 2 == 1 }
    println(indexedResult === indexedDestination)
    println(indexedDestination)

    println(values.filterIsInstance<String>())
    val instanceDestination = mutableListOf("seed")
    val instanceResult = values.filterIsInstanceTo(instanceDestination)
    println(instanceResult === instanceDestination)
    println(instanceDestination)

    println(values.filterNot { it == null })
    val notDestination = mutableListOf<Any?>("seed")
    println(values.filterNotTo(notDestination) { it == null } === notDestination)
    println(notDestination)

    val nullable: Iterable<String?> = listOf("a", null, "b")
    println(nullable.filterNotNull())
    val notNullDestination = mutableListOf("seed")
    println(nullable.filterNotNullTo(notNullDestination) === notNullDestination)
    println(notNullDestination)

    val toDestination = mutableListOf<Any?>("seed")
    println(values.filterTo(toDestination) { it != null } === toDestination)
    println(toDestination)

    val custom: Iterable<Int> = Counter(4)
    println(custom.filter { it % 2 == 0 })
    println(custom.filterNot { it % 2 == 0 })
    val customDestination = mutableListOf(99)
    println(custom.filterTo(customDestination) { it > 1 })

    val oneShot: Iterable<Int> = OneShot(listOf(1, 2, 3))
    println(oneShot.filter { it > 1 })

    var predicateCalls = 0
    println(values.filter {
        predicateCalls++
        it != null
    })
    println(predicateCalls)

    val hierarchy: Iterable<Any?> = listOf(Child(), Parent("parent"), null)
    println(hierarchy.filterIsInstance<Parent>().size)
    println(hierarchy.filterIsInstance<Child>().size)

    try {
        listOf(1, 2, 3).filter {
            if (it == 2) throw IllegalStateException("stop")
            true
        }
        println("missing")
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
