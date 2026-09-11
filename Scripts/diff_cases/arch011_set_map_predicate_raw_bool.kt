fun check(s: Set<Int>, x: Int): Boolean = x in s

fun main() {
    val m = mutableMapOf(1 to 2)
    if (m.isEmpty()) println("empty") else println("not empty")
    val e = m.isEmpty()
    if (e) println("e true") else println("e false")
    println(!m.isEmpty())

    val s = setOf(1, 2, 3)
    if (2 in s) println("2 in s") else println("2 not in s")
    if (5 in s) println("5 in s") else println("5 not in s")
    println(s.contains(2))
    println(s.contains(5))
    println(s.isEmpty())
    println(check(s, 3))
    println(check(s, 9))

    val ms = mutableSetOf(1, 2, 3)
    if (ms.add(4)) println("add 4 true") else println("add 4 false")
    if (ms.add(4)) println("add 4 again true") else println("add 4 again false")
    println(ms.add(5))
    println(ms.add(5))
    if (ms.remove(5)) println("remove 5 true") else println("remove 5 false")
    if (ms.remove(99)) println("remove 99 true") else println("remove 99 false")
    println(ms.remove(1))
    println(ms.remove(99))
    if (ms.removeAll(listOf(2, 3))) println("removeAll true") else println("removeAll false")
    if (ms.removeAll(listOf(7, 8))) println("removeAll none true") else println("removeAll none false")
    println(ms.removeAll(listOf(4)))
    println(ms)
    if (ms.retainAll(listOf(1, 4))) println("retainAll true") else println("retainAll false")
    println(ms.retainAll(listOf(1, 4)))
    println(ms)

    val b: Boolean = ms.contains(2)
    val a: Any = b
    println(a)
    println(b == true)
}
