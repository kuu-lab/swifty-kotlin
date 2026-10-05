class Bucket : Iterable<Int> {
    override fun iterator(): Iterator<Int> = listOf(1, 2, 3).iterator()
    operator fun contains(value: Any?): Boolean = value is String
}

operator fun IntRange.contains(value: String): Boolean = value == "custom"

fun rangeBranch(x: Any?): String = when (x) {
    in 1..3 -> "range"
    else -> "other"
}

fun checkMembership(x: Any?) {
    println(x in 1..3)
    println(x !in 1..3)
    println(rangeBranch(x))
    println(x in listOf(1, 2, 3))
    println(x !in setOf(1, 2, 3))
    val iterable: Iterable<Int> = listOf(1, 2, 3)
    println(iterable.contains(x))
    println((1..3).contains(x))
    println(x in 1L..3L)
    println(x in 'a'..'c')
}

fun main() {
    val number: Any = 2
    val text: Any = "a"
    println(number in 1..3)
    println(text in 1..3)
    checkMembership(number)
    checkMembership(text)
    checkMembership(2L)
    checkMembership(2.toByte())
    checkMembership(2.toShort())
    checkMembership(2u)
    checkMembership('b')
    checkMembership(null)
    println(null in listOf<Int?>(1, null))
    println(2 in Bucket())
    println("a" in Bucket())
    println("custom" in 1..3)
    println(2 in 1..3)
}
