import java.util.Arrays.sort

fun main() {
    val fullyQualified = intArrayOf(9, 1, 7, 3)
    java.util.Arrays.sort(fullyQualified)
    println(fullyQualified.joinToString(","))

    val empty = intArrayOf()
    sort(empty)
    println(empty.joinToString(","))

    val duplicatesAndNegatives = intArrayOf(7, -2, 7, 0, -2)
    sort(duplicatesAndNegatives)
    println(duplicatesAndNegatives.joinToString(","))

    val boundaries = intArrayOf(Int.MAX_VALUE, 0, Int.MIN_VALUE, -1, Int.MIN_VALUE, Int.MAX_VALUE)
    java.util.Arrays.sort(boundaries)
    println(boundaries.joinToString(","))

    val nullable: IntArray? = null
    try {
        sort(nullable)
        println("null:no-throw")
    } catch (error: NullPointerException) {
        println("null:npe")
    }
}
