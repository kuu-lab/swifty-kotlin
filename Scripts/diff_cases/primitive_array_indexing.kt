// KUU-2819: indexing extensions cover every primitive-array receiver type.
fun main() {
    val doubles = doubleArrayOf(1.5, 2.5, 1.5)
    println(doubles.lastIndex)
    println(doubles.indices)

    val floats = floatArrayOf(1.5f, 2.5f, 1.5f)
    println(floats.lastIndex)
    println(floats.indices)

    val shorts = shortArrayOf(1, 2, 1)
    println(shorts.lastIndex)
    println(shorts.indices)
    println(shorts.indexOf(2))
    println(shorts.indexOf(3))

    val booleans = booleanArrayOf(true, false, true)
    println(booleans.lastIndex)
    println(booleans.indices)
    println(booleans.indexOf(true))
    println(booleans.indexOf(false))
}
