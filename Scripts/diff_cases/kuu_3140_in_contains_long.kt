class LongR {
    operator fun contains(l: Long): Boolean = l == 5L
}

class IntR {
    operator fun contains(i: Int): Boolean = i == 5
}

class IntOrLong {
    operator fun contains(i: Int): Boolean = i == 5
    operator fun contains(l: Long): Boolean = l == 7L
}

fun box(): String = if (5 in LongR()) "OK" else "FAIL"

fun main() {
    println(box())
    println(5 in LongR())
    println(6 in LongR())
    println(5 !in LongR())
    println(5L in LongR())
    println(5 in IntR())
    println(LongR().contains(5))
    println(5 in IntOrLong())
    println(7 in IntOrLong())
    println(7L in IntOrLong())
}
