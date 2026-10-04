@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")

fun main() {
    val zero = UInt(0)
    val one = UInt(1)
    val allBits = UInt(-1)
    val min = UInt(Int.MIN_VALUE)
    val max = UInt(Int.MAX_VALUE)
    val inferred = UInt(-1)
    val boxed: Any = allBits

    println(zero)
    println(one)
    println(allBits)
    println(min)
    println(max)
    println(inferred == allBits)
    println(boxed is UInt)
}
