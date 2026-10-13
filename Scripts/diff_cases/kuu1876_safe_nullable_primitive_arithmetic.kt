var argumentEvaluations = 0

fun nextFloatForSafeNullablePrimitiveArithmetic(): Float {
    argumentEvaluations += 1
    return 1f
}

fun main() {
    val f: Float? = 1.5f
    val noFloat: Float? = null
    val d: Double? = -3.5
    val noDouble: Double? = null
    val c: Char? = 'B'
    val noChar: Char? = null

    println(f?.plus(1f))
    println(f?.minus(1f))
    println(f?.times(2f))
    println(f?.div(2f))
    println(f?.rem(1f))
    println(f?.mod(1f))
    println(d?.plus(2.0))
    println(d?.minus(2.0))
    println(d?.times(2.0))
    println(d?.div(2.0))
    println(d?.rem(2.0))
    println(d?.mod(2.0))
    println(c?.plus(2))
    println(c?.minus(1))

    println(noFloat?.plus(1f))
    println(noFloat?.minus(1f))
    println(noFloat?.times(2f))
    println(noFloat?.div(2f))
    println(noFloat?.rem(1f))
    println(noFloat?.mod(1f))
    println(noDouble?.plus(2.0))
    println(noDouble?.minus(2.0))
    println(noDouble?.times(2.0))
    println(noDouble?.div(2.0))
    println(noDouble?.rem(2.0))
    println(noDouble?.mod(2.0))
    println(noChar?.plus(2))
    println(noChar?.minus(1))
    println(noFloat?.plus(nextFloatForSafeNullablePrimitiveArithmetic()))
    println(argumentEvaluations)
}
