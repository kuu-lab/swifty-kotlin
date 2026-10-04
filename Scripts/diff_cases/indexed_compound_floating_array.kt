// Regression for indexed compound assignment on boxed floating-point arrays.
// Array<Double>/Array<Float> stores boxed elements, but arithmetic must use the
// floating-point runtime ABI after the element is unboxed.
fun main() {
    val doubles = arrayOf(1.5, 2.5)
    doubles[0] += 0.5
    doubles[1] -= 0.5
    doubles[0] *= 2.0
    doubles[1] /= 2.0
    doubles[0] %= 0.75
    println(doubles[0])
    println(doubles[1])

    val floats = arrayOf(1.5f, 2.5f)
    floats[0] += 0.5f
    floats[1] -= 0.5f
    floats[0] *= 2.0f
    floats[1] /= 2.0f
    floats[0] %= 0.75f
    println(floats[0])
    println(floats[1])

    val primitiveDoubles = doubleArrayOf(1.5, 2.5)
    primitiveDoubles[0] += 0.5
    primitiveDoubles[1] -= 0.5
    primitiveDoubles[0] *= 2.0
    primitiveDoubles[1] /= 2.0
    primitiveDoubles[0] %= 0.75
    println(primitiveDoubles[0])
    println(primitiveDoubles[1])

    val primitiveFloats = floatArrayOf(1.5f, 2.5f)
    primitiveFloats[0] += 0.5f
    primitiveFloats[1] -= 0.5f
    primitiveFloats[0] *= 2.0f
    primitiveFloats[1] /= 2.0f
    primitiveFloats[0] %= 0.75f
    println(primitiveFloats[0])
    println(primitiveFloats[1])
}
