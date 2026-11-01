import java.util.Arrays.sort

fun main() {
    val values = intArrayOf(9, 1, 7, 3)
    sort(values)
    println(values.joinToString(","))

    val extensionCall = intArrayOf(5, 4, 6)
    extensionCall.sort()
    println(extensionCall.joinToString(","))

    val qualified = intArrayOf(3, 1, 2)
    java.util.Arrays.sort(qualified)
    println(qualified.joinToString(","))
}
