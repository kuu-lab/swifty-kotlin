fun ClosedFloatingPointRange<Double>.toList(): List<Double> = listOf(start, endInclusive)
fun ClosedFloatingPointRange<Double>.endExclusive(dummy: Int): Double = 42.0
fun OpenEndRange<Double>.endExclusive(dummy: Int): Double = 43.0
fun OpenEndRange<Double>.endExclusive(): Double = 44.0

fun main() {
    val doubles = 1.0..3.0
    println(doubles.start)
    println(doubles.endInclusive)
    println(doubles.contains(2.0))
    println(doubles.isEmpty())
    println(2.0 in doubles)
    println(doubles.toList())
    println((1.0..3.0).toList())
    val floats = 1f..3f
    println(floats.start)
    println(floats.endInclusive)
    println(floats.contains(2f))
    println(floats.isEmpty())
    val open = 1.0..<3.0
    println(open.start)
    println(open.endExclusive)
    println(3.0 in open)
    val floatOpen = 1f..<3f
    println(floatOpen.start)
    println(floatOpen.endExclusive)
    println(3f in floatOpen)
    println(doubles.endExclusive(1))
    println(open.endExclusive(1))
    println(open.endExclusive())
    println((1..3).toList())
    println((1L..3L).toList())
}
