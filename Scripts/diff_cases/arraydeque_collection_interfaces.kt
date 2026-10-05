fun <T> collectionCopy(values: Iterable<T>): List<T> = values.toList()

fun throughInterfaces(list: List<Int>, collection: Collection<Int>, iterable: Iterable<Int>) {
    println(list.listIterator(1).previous())
    println(list.subList(0, 1))
    println(collection.contains(2))
    println(iterable.iterator().next())
    var total = 0
    for (element in iterable) total += element
    println(total)
}

fun compareErased(value: Any, other: Any) {
    println(value == other)
    println(value.hashCode() == other.hashCode())
    println(value)
}

fun inspectDeque(value: Any) {
    println(value is ArrayDeque<*>)
    println(value is AbstractMutableList<*>)
    println(value is MutableList<*>)
    println(value is List<*>)
    println(value is MutableCollection<*>)
    println(value is Collection<*>)
    println(value is Iterable<*>)
    println(value is Set<*>)
}

fun main() {
    val d = ArrayDeque<Int>()
    d.addLast(1)
    d.addLast(2)
    val l: List<Int> = d
    val c: Collection<Int> = d
    val i: Iterable<Int> = d
    val m: MutableList<Int> = d
    println(d.iterator().next())
    println(d.map { it * 2 })
    println(d.elementAt(0))
    println(d.getOrNull(9))
    println(d.getOrElse(9) { 42 })
    println(d.toList())
    println(d.sum())
    println(l[1])
    println(c.size)
    println(i.filter { it > 1 })
    println(collectionCopy(d))
    inspectDeque(d)
    throughInterfaces(d, d, d)
    compareErased(d, listOf(1, 2))
    println(setOf<Any>(d, d.toList()).size)
    val lookup = mapOf<Any, String>(d to "deque")
    println(lookup[d.toList()])

    m.add(3)
    m.add(1, 9)
    println(m.set(0, 7))
    println(d.toString())
    println(l.toList())
    println(c.containsAll(listOf(7, 9)))
    println(d.containsAll(listOf(7, 9)))
    println(m.removeAt(1))
    println(m.remove(2))
    println(d.toString())
    println(m.addAll(d))
    println(d.toString())

    val iter = d.iterator()
    println(iter.next())
    iter.remove()
    println(d.toString())
    val li = d.listIterator(1)
    println(li.previous())
    li.set(30)
    li.add(10)
    println(d.toString())
    val sub = d.subList(1, 3)
    println(sub.toList())
    sub[0] = 40
    sub.add(50)
    println(d.toString())
    println(l.toList())

    val beforeSet = d.iterator()
    d[0] = 60
    println(beforeSet.next())
    val stale = d.iterator()
    d.addFirst(0)
    try {
        stale.next()
        println("missing concurrent modification")
    } catch (e: ConcurrentModificationException) {
        println("concurrent modification")
    }

    val ring = ArrayDeque<Int>(8)
    var n = 0
    while (n < 12) {
        ring.addLast(n)
        n += 1
    }
    repeat(9) { ring.removeFirst() }
    repeat(12) { ring.addLast(100 + it) }
    println(ring.toList())
    println(ring.map { it + 1 })
    println(ArrayDeque<Int>(ring).toList())
    println(ring == ring.toList())
    println(ring.hashCode() == ring.toList().hashCode())

    val nullable = ArrayDeque<String?>()
    nullable.addLast(null)
    nullable.addLast("hello")
    println(nullable.toList())
    println(nullable.map { it ?: "null" })
    println(collectionCopy(nullable))
    val empty = ArrayDeque<Int>()
    println(empty.toList())
    println(empty.iterator().hasNext())
    println(empty.getOrNull(0))
    try {
        empty.iterator().next()
    } catch (e: NoSuchElementException) {
        println("empty iterator")
    }
    try {
        d.listIterator(-1)
    } catch (e: IndexOutOfBoundsException) {
        println("iterator bounds")
    }
    try {
        d.set(d.size, 99)
    } catch (e: IndexOutOfBoundsException) {
        println("set bounds")
    }
    try {
        d.subList(2, 1)
    } catch (e: IllegalArgumentException) {
        println("sublist bounds")
    }
    val mc: MutableCollection<Int> = d
    mc.clear()
    println(d.size)
    println(l.isEmpty())
}
