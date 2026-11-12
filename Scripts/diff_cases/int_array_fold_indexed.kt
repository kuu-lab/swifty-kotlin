// DIFF_JVM
fun weightedSum(): Int = intArrayOf(1, 2, 3).foldIndexed(0) { index, acc, value -> acc + index * value }

fun main() {
    println(weightedSum())

    val ordered = intArrayOf(5, 7, 11).foldIndexed("") { index, acc, value ->
        if (index == 0) "$index:$value" else "$acc,$index:$value"
    }
    println(ordered)

    var lambdaCalls = 0
    val emptyResult = intArrayOf().foldIndexed(41) { _, acc, _ ->
        lambdaCalls += 1
        acc + 1
    }
    println("$emptyResult:$lambdaCalls")
}
