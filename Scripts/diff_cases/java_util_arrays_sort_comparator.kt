import java.util.Arrays
import java.util.Comparator

fun main() {
    val words = arrayOf("b", "a", "c")
    Arrays.sort(words) { first, second -> first.compareTo(second) }
    println(Arrays.toString(words))

    val reversed = arrayOf("a", "c", "b")
    Arrays.sort(reversed) { first, second -> second.compareTo(first) }
    println(Arrays.toString(reversed))

    val ranged = arrayOf("d", "a", "c", "b")
    Arrays.sort(ranged, 1, 3) { first, second -> second.compareTo(first) }
    println(Arrays.toString(ranged))

    val explicit = arrayOf(3, 1, 2)
    val byOnes = Comparator<Int> { first, second -> first % 10 - second % 10 }
    Arrays.sort(explicit, byOnes)
    println(Arrays.toString(explicit))

    val natural = arrayOf("d", "c")
    Arrays.sort(natural, null)
    println(Arrays.toString(natural))

    val rangedNatural = arrayOf("f", "e", "d", "c")
    Arrays.sort(rangedNatural, 1, 3, null)
    println(Arrays.toString(rangedNatural))

    val parallel = arrayOf("b", "a")
    Arrays.parallelSort(parallel) { first, second -> first.compareTo(second) }
    println(Arrays.toString(parallel))

    val parallelRanged = arrayOf(4, 1, 3, 2)
    Arrays.parallelSort(parallelRanged, 1, 3) { first, second -> second - first }
    println(Arrays.toString(parallelRanged))
}
