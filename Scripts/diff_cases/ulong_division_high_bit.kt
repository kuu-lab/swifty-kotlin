fun main() {
    val big: ULong = 17663719463477156090uL
    println(big / 2uL)
    println(big % 7uL)
    println(big % 1000uL)
    println(big.div(2uL))
    println(big.rem(1000uL))
    println(big.floorDiv(2uL))
    println(ULong.MAX_VALUE / big)
    println(ULong.MAX_VALUE % big)

    var mutableBig: ULong = big
    mutableBig /= 2uL
    println(mutableBig)

    val zero: ULong = 0uL
    try {
        println(big / zero)
    } catch (e: ArithmeticException) {
        println("div by zero caught")
    }
    try {
        println(big % zero)
    } catch (e: ArithmeticException) {
        println("rem by zero caught")
    }
}
