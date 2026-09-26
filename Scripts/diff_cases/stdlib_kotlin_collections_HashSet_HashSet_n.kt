fun main() {
    val set = HashSet<String?>()
    println(set.isEmpty())
    println(set.size)
    println(set.add("a"))
    println(set.add("b"))
    println(set.add("a"))
    println(set.size)
    println(set.contains("a"))
    println(set.contains("c"))
    println(set.add(null))
    println(set.contains(null))

    val copy = HashSet(set)
    println(copy.size)
    println(copy == set)

    println(set.remove("b"))
    println(set.remove("missing"))
    println(set.size)

    val extra = HashSet<String?>()
    extra.add("x")
    extra.add("a")
    println(set.addAll(extra))
    println(set.addAll(extra))
    println(set.size)

    println(set.removeAll(listOf("x", "nope")))
    println(set.size)
    println(set.retainAll(listOf("a", null)))
    println(set.size)

    // HashSet iteration order is implementation-defined; sort for a stable oracle.
    val sorted = set.toList().sortedBy { it ?: "" }
    println(sorted.joinToString(","))

    val iter = set.iterator()
    var iterated = 0
    while (iter.hasNext()) {
        iter.next()
        iterated += 1
    }
    println(iterated)

    val viaInterface: MutableSet<String?> = set
    println(viaInterface.isEmpty())

    set.clear()
    println(set.isEmpty())
    println(set.size)
    println(set.isEmpty() && set.size == 0)
}
