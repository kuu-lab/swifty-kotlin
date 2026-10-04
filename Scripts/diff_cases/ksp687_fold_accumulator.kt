// KSP-687 regression: primitive-array fold accumulators keep the source type.
fun main() {
    val doubles = doubleArrayOf(1.0, 2.5, 3.5)
    println(doubles.fold(0.0) { accumulator, value -> accumulator + value })
    println(doubles.foldIndexed(0.0) { index, accumulator, value -> accumulator + index * value })

    val floats = floatArrayOf(1.0f, 2.5f)
    println(floats.fold(0.0f) { accumulator, value -> accumulator + value })
}
