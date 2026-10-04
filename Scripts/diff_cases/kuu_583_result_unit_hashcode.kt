fun main() {
    val intResultHash: Int = Result.success(1).hashCode()
    val stringResultHash: Int = Result.success("abc").hashCode()
    val firstHash: Int = Result.success(1).hashCode()
    val secondHash: Int = Result.success(1).hashCode()
    val nullResultHash: Int = Result.success(null).hashCode()
    val exception = IllegalStateException("x")
    val failureHash: Int = Result.failure<Int>(exception).hashCode()
    val unitHash: Int = Unit.hashCode()

    println(intResultHash)
    println(stringResultHash)
    println(firstHash == secondHash)
    println(nullResultHash)
    println(failureHash == exception.hashCode())
    println(unitHash >= -2_147_483_648 && unitHash <= 2_147_483_647)
}
