fun sum(values: IntArray): Int { var total = 0; for (value in values) { total += value }; return total }
fun main() {
    val values = intArrayOf(2, 3, 4)
    values[1] = 8
    values[2] += 1
    println(values.size)
    println(sum(values))
    val zero = LongArray(2)
    zero[0] = 9L
    println(zero[0] + zero[1])
    val words = arrayOf("one", "two")
    words[1] = "three"
    for (word in words) { println(word) }
    val nullable = arrayOfNulls<String>(2)
    nullable[0] = "ok"
    println(nullable[0])
    println(nullable[1])
    val nested = arrayOf(intArrayOf(6))
    println(nested[0][0])
    println(booleanArrayOf(true, false)[1])
    println(doubleArrayOf(1.5, 2.5)[0])
}
