// KUU-1897: native heap ordering, duplicate retention, and queue boundaries.
import java.util.PriorityQueue

interface Tagged { fun tag(): Int }
class Work(val cost: Int) : Tagged, Comparable<Work> {
    override fun tag(): Int = cost
    override fun compareTo(other: Work): Int = cost.compareTo(other.cost)
}
data class Job(val cost: Int)

fun <T> drain(queue: PriorityQueue<T>): List<T> {
    val values = mutableListOf<T>()
    while (queue.isNotEmpty()) values.add(queue.remove())
    return values
}

fun main() {
    val natural = PriorityQueue<Int>(1)
    for (value in listOf(3, Int.MIN_VALUE, 1, 3, 0, Int.MAX_VALUE, -1)) natural.add(value)
    println(natural.size)
    println(natural.peek())
    println(natural.element())
    println(drain(natural))
    println(natural.isEmpty())
    println(natural.poll() == null)
    println(natural.peek() == null)
    try { natural.remove() } catch (e: NoSuchElementException) { println("empty-remove") }
    try { natural.element() } catch (e: NoSuchElementException) { println("empty-element") }

    val descending = PriorityQueue<Int>(2, Comparator { a, b -> b.compareTo(a) })
    for (value in listOf(2, 5, 1, 5, 3)) descending.offer(value)
    println(drain(descending))
    val nullOrder: Comparator<Int>? = null
    val nullComparator = PriorityQueue<Int>(nullOrder)
    nullComparator.add(2)
    nullComparator.add(1)
    println(nullComparator.comparator() == null)
    println(drain(nullComparator))

    val works = PriorityQueue<Work>()
    works += Work(9)
    works += Work(2)
    works += Work(2)
    println(works.poll()!!.cost)
    println(works.remove().cost)
    println(works.remove().cost)
    println(works.isEmpty())

    val byCost: Comparator<Job> = compareBy { it.cost }
    val jobs = PriorityQueue<Job>(byCost)
    jobs.add(Job(7))
    jobs.add(Job(1))
    println(jobs.comparator() === byCost)
    println(jobs.remove().cost)
    println(jobs.remove().cost)

    val words = PriorityQueue<String>()
    words.add("z")
    words.add("aa")
    words.add("a")
    println(drain(words))

    for (capacity in listOf(0, -1)) {
        try { PriorityQueue<Int>(capacity) } catch (e: IllegalArgumentException) { println("bad-capacity") }
    }
    val nullable = PriorityQueue<Int?>()
    try { nullable.add(null) } catch (e: NullPointerException) { println("null-element") }
    println(nullable.isEmpty())
    nullable.add(Int.MIN_VALUE)
    nullable.offer(1)
    println(drain(nullable))
    val nullableWords = PriorityQueue<String?>()
    try { nullableWords.offer(null) } catch (e: NullPointerException) { println("null-string") }
    nullableWords.add("a")
    println(nullableWords.remove())
    val nonComparable = PriorityQueue<Any>()
    try { nonComparable.add(Any()) } catch (e: ClassCastException) { println("non-comparable") }
    println(nonComparable.isEmpty())
    val throwing = PriorityQueue<Int>(Comparator { _, _ -> throw IllegalArgumentException("compare") })
    throwing.add(1)
    try { throwing.add(2) } catch (e: IllegalArgumentException) { println(e.message) }
    println(throwing.size)

    val removed = PriorityQueue<Int>()
    for (value in listOf(1, 4, 2, 5, 6, 3, 7)) removed.add(value)
    println(removed.remove(4))
    println(removed.remove(9))
    println(drain(removed))

    val repairUp = PriorityQueue<Int>()
    for (value in listOf(1, 4, 2, 6, 5, 3)) repairUp.add(value)
    println(repairUp.remove(6))
    println(drain(repairUp))

    val iterated = PriorityQueue<Int>()
    for (value in listOf(5, 2, 4, 1, 3, 2)) iterated.add(value)
    val iterator = iterated.iterator()
    var visited = 0
    while (iterator.hasNext()) {
        val value = iterator.next()
        visited += 1
        if (value % 2 == 0) iterator.remove()
    }
    println(visited)
    println(drain(iterated))
    iterated.add(3)
    iterated.clear()
    println(iterated.isEmpty())

    val chars = PriorityQueue<Char>(Comparator { a, b -> a.code.compareTo(b.code) })
    chars.add(256.toChar())
    val charIterator = chars.iterator()
    println(charIterator.next().code)
    charIterator.remove()
    println(chars.isEmpty())
}
