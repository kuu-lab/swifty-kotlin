// KUU-4026: removeIf resolves on JVM as the java.util.Collection default
// method, so it must be available on every MutableCollection receiver —
// MutableList, MutableSet, and the MutableMap entries/keys/values views —
// removing through MutableIterator.remove and returning whether the
// collection changed.
fun main() {
    val l = mutableListOf(1, 2, 3, 4)
    println(l.removeIf { it % 2 == 0 })
    println(l)
    println(l.removeIf { it > 10 })

    val s = mutableSetOf(1, 2, 3, 4)
    println(s.removeIf { it % 2 == 0 })
    println(s)

    val ls = linkedSetOf(1, 2, 3, 4)
    println(ls.removeIf { it < 3 })
    println(ls)

    val m = mutableMapOf(1 to "a", 2 to "b", 3 to "c")
    println(m.entries.removeIf { it.key == 2 })
    println(m)
    println(m.keys.removeIf { it == 1 })
    println(m)
    println(m.values.removeIf { it == "c" })
    println(m)

    val ll = java.util.LinkedList<Int>()
    ll.add(1)
    ll.add(2)
    ll.add(3)
    println(ll.removeIf { it == 2 })
    println(ll)

    val dq = ArrayDeque<Int>()
    dq.add(1)
    dq.add(2)
    dq.add(3)
    println(dq.removeIf { it == 2 })
    println(dq)

    val typed: MutableCollection<Int> = mutableListOf(5, 6, 7)
    println(typed.removeIf { it < 7 })
    println(typed)
}
