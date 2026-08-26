fun main() {
    val genericA: Array<Int?> = arrayOf(1, null, 3)
    val genericB: Array<Int?> = arrayOf(1, null, 3)
    val genericC: Array<Int?> = arrayOf(1, 2, 3)
    println(genericA.contentEquals(genericB))
    println(genericA.contentEquals(genericC))
    println(genericA.contentEquals(null))
    val nullableGeneric: Array<Int>? = null
    println(nullableGeneric.contentEquals(null))
    println(genericA.contentHashCode() == genericB.contentHashCode())
    println(genericA.contentToString())

    val nested: Array<Any?> = arrayOf(
        arrayOf(arrayOf(1, 2)),
        intArrayOf(3, 4),
        arrayOfNulls<String>(1)
    )
    val nestedSame: Array<Any?> = arrayOf(
        arrayOf(arrayOf(1, 2)),
        intArrayOf(3, 4),
        arrayOfNulls<String>(1)
    )
    println(nested.contentDeepEquals(nestedSame))
    println(nested.contentDeepHashCode() == nestedSame.contentDeepHashCode())
    println(nested.contentDeepToString())

    val self: Array<Any?> = arrayOfNulls(1)
    self[0] = self
    println(self.contentDeepEquals(self))
    println(self.contentDeepToString())

    val floats = floatArrayOf(Float.NaN, -0.0f)
    val sameFloats = floatArrayOf(Float.NaN, -0.0f)
    val differentZero = floatArrayOf(Float.NaN, 0.0f)
    println(floats.contentEquals(sameFloats))
    println(floats.contentEquals(differentZero))
    println(floats.contentHashCode() == sameFloats.contentHashCode())
    println(floats.contentToString())

    val unsigned = uintArrayOf(1u, 4_000_000_000u)
    val sameUnsigned = uintArrayOf(1u, 4_000_000_000u)
    println(unsigned.contentEquals(sameUnsigned))
    println(unsigned.contentHashCode() == sameUnsigned.contentHashCode())
    println(unsigned.contentToString())
    println(unsigned.contentEquals(null))
}
