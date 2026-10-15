fun main() {
    val booleans = booleanArrayOf(true, false).iterator()
    println(booleans.hasNext())
    println(booleans.next())
    println(booleans.next())
    println(booleans.hasNext())

    val chars = charArrayOf('a', 'b').iterator()
    println(chars.hasNext())
    println(chars.next())

    val doubles = doubleArrayOf(1.5, 2.5).iterator()
    println(doubles.hasNext())
    println(doubles.next())

    val floats = floatArrayOf(3.5f, 4.5f).iterator()
    println(floats.hasNext())
    println(floats.next())

    for (value in booleanArrayOf(false, true)) println(value)
}
