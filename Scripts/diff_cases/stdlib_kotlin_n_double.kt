fun main() {
    val values = doubleArrayOf(1.5, -2.0, 3.25)
    val spreadValues = doubleArrayOf(4.0, 5.0)
    val spreadResult = doubleArrayOf(-1.0, *spreadValues, 6.0)
    println(values.size)
    println(values[0] == 1.5)
    println(values[1] == -2.0)
    println(spreadResult.size)
    println(spreadResult[1] == 4.0)
    println(spreadResult[2] == 5.0)
    println(spreadResult[3] == 6.0)

    val spreadOnlySource = doubleArrayOf(7.0, 8.0)
    val spreadOnlyCopy = doubleArrayOf(*spreadOnlySource)
    spreadOnlyCopy[0] = 9.0
    println(spreadOnlySource[0] == 7.0)
    println(spreadOnlyCopy[0] == 9.0)

    println((-1.5).toUInt())
    println(3.99.toUInt())
    println(4294967296.0.toUInt())
    println(Double.NaN.toUInt())

    println((-1.5).toULong())
    println(3.99.toULong())
    println(Long.MAX_VALUE.toDouble().toULong())
    println(1.0e19.toULong())
    println(Double.NaN.toULong())
    println(Double.POSITIVE_INFINITY.toULong())
}
