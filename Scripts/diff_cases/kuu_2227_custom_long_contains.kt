class LongR {
    operator fun contains(value: Long): Boolean = value == 5L
}

class IntOrLong {
    operator fun contains(value: Int): Boolean = value == 5
    operator fun contains(value: Long): Boolean = value == 5L
}

fun main() {
    println(5 in LongR())
    println(5 !in LongR())
    println(6 !in LongR())
    println(5L in LongR())
    println(5 in IntOrLong())
    println(5L in IntOrLong())
    val explicitInt: Int = 5
    println(explicitInt in IntOrLong())
    println(LongR().contains(5))
}
