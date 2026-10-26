// KUU-3347: for-in must bind the user-defined ClosedRange<Double>.iterator().
operator fun ClosedRange<Double>.iterator() = object : Iterator<Double> {
    private var cur = start
    override fun hasNext() = cur <= endInclusive
    override fun next(): Double { val n = cur; cur += 0.1; return n }
}

fun main() {
    var sum = 0.0
    for (value in 0.0..1.0) sum += value
    println(sum)
}
