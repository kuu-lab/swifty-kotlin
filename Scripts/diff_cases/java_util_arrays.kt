import java.util.Arrays

fun main() {
    println(Arrays.asList("a", "b"))
    println(Arrays.asList(1, 2))

    val integers = intArrayOf(4, 2, 6)
    Arrays.fill(integers, 1, 2, 5)
    println(Arrays.toString(integers))
    println(Arrays.binarySearch(intArrayOf(1, 3, 5), 3))
    println(Arrays.binarySearch(intArrayOf(1, 3, 5), 4))
    println(Arrays.equals(intArrayOf(1, 2), intArrayOf(1, 2)))
    println(Arrays.hashCode(intArrayOf(1, 2)))
    println(Arrays.toString(Arrays.copyOf(integers, 5)))
    println(Arrays.toString(Arrays.copyOfRange(integers, 1, 5)))

    val names = arrayOf("b", "a")
    Arrays.fill(names, 1, 2, "c")
    println(Arrays.toString(names))
    println(Arrays.equals(names, arrayOf("b", "c")))
    println(Arrays.binarySearch(arrayOf("a", "b", "c"), "b"))
    println(Arrays.toString(Arrays.copyOfRange(names, 1, 4)))

    val words = arrayOf("c", "a", "b")
    Arrays.sort(words)
    println(Arrays.toString(words))
    Arrays.parallelSort(integers)
    println(Arrays.toString(integers))
    val decimals = doubleArrayOf(Double.NaN, 0.0, -0.0, 2.0)
    Arrays.sort(decimals)
    println(Arrays.toString(decimals))

    val nested = arrayOf<Any>(arrayOf(1, 2), intArrayOf(3, 4))
    println(Arrays.deepToString(nested))
    println(Arrays.deepEquals(nested, arrayOf<Any>(arrayOf(1, 2), intArrayOf(3, 4))))
    println(Arrays.deepHashCode(nested) == Arrays.deepHashCode(arrayOf<Any>(arrayOf(1, 2), intArrayOf(3, 4))))
    println(Arrays.mismatch(intArrayOf(1, 2), intArrayOf(1, 3)))
    println(Arrays.mismatch(doubleArrayOf(Double.NaN), doubleArrayOf(Double.NaN)))
    println(Arrays.toString(null as IntArray?))
    println(Arrays.equals(null as IntArray?, null))
}
