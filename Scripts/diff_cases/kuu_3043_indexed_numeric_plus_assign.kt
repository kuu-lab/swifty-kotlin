fun main() {
    val longs = mutableListOf(0L, 0L, 0L)
    longs[1] += 5
    println(longs)

    val doubles = mutableListOf(0.0, 0.0)
    doubles[1] += 5
    println(doubles)

    val ints = mutableListOf(0, 0, 0)
    ints[1] += 5
    println(ints)
}
