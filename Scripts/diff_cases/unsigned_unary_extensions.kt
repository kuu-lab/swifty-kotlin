operator fun UByte.unaryMinus(): Int = 11
operator fun UShort.unaryMinus(): Int = 12
operator fun UInt.unaryMinus(): Int = 13
operator fun ULong.unaryMinus(): Int = 14
operator fun UByte.unaryPlus(): Int = 21
operator fun UShort.unaryPlus(): Int = 22
operator fun UInt.unaryPlus(): Int = 23
operator fun ULong.unaryPlus(): Int = 24

fun operand(): UInt {
    println("operand")
    return 1u
}

fun main() {
    val ub: UByte = 1u
    val us: UShort = 1u
    val ui: UInt = 1u
    val ul: ULong = 1uL
    println(-ub)
    println(-us)
    println(-ui)
    println(-ul)
    println(-1u)
    println(-1uL)
    println(-operand())
    println(+ub)
    println(+us)
    println(+ui)
    println(+ul)
    println(+1u)
    println(+1uL)
    println(-1)
    println(-1L)
    println(-1.5f)
    println(-1.5)
    println(0u - 1u)
    println(0uL - 1uL)
}
