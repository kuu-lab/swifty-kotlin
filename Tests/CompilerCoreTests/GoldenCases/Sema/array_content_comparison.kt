fun inspect(
    values: Array<Int?>,
    nested: Array<Any?>,
    ints: IntArray,
    uints: UIntArray,
    floats: FloatArray
) {
    val shallowEqual = values.contentEquals(null)
    val shallowHash = values.contentHashCode()
    val shallowText = values.contentToString()
    val deepEqual = nested.contentDeepEquals(null)
    val deepHash = nested.contentDeepHashCode()
    val deepText = nested.contentDeepToString()
    val intEqual = ints.contentEquals(null)
    val uintHash = uints.contentHashCode()
    val floatText = floats.contentToString()
}
