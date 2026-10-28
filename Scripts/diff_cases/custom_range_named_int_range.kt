class IntRange {
    operator fun contains(a: Int) = (1..2).contains(a)
}

class C {
    operator fun rangeTo(i: Int): IntRange = IntRange()
    operator fun rangeTo(i: Double): IntRange = IntRange()
}

fun main() {
    println(2 in C()..2)
    println(3 in C()..2)
    println(3 !in C()..2)
    val range = C()..2
    println(1 in range)
    println(range.contains(3))
    println(2 in 1..2)
    println(2 in C()..2.0)
}
