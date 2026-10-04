fun main() {
    val list = listOf(1, 2, 3)
    val reduced = list.reduceIndexed { index, acc, value -> acc + index + value }
    println(reduced)

    val running = list.runningReduceIndexed { index, acc, value -> acc + index + value }
    var i = 0
    while (i < running.size) {
        println(running[i])
        i += 1
    }
}
