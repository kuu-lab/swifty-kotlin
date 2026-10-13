// KUU-1366: ArrayDeque<E> : AbstractMutableList<E> — collection extensions,
// member iterator(), `is` checks, and interface dispatch all agree with JVM.

fun main() {
    val d = ArrayDeque(listOf(1, 2, 3))

    // Collection extensions that failed to resolve while ArrayDeque had no supertype.
    println(d.toList())
    println(d.map { it * 2 })
    println(d.singleOrNull() ?: "not-single")
    println(ArrayDeque(listOf(7)).singleOrNull())

    // Member iterator() and static-type for-in.
    println(d.iterator().next())
    val buf = StringBuilder()
    for (x in d) buf.append(x).append(';')
    println(buf.toString())

    // Static `is` checks fold through the declared hierarchy.
    println(d is List<Int>)
    println(d is Collection<Int>)
    println(d is MutableList<Int>)
    println(d is Iterable<Int>)

    // MutableList-typed receivers dispatch to deque members.
    val m: MutableList<Int> = d
    m[0] = 0
    m.add(1, 9)
    println(m.removeAt(2))
    println(d.toList())
    println(m.removeFirst())
    println(m.removeLast())
    println(m.first())
    println(m.toList())
}
