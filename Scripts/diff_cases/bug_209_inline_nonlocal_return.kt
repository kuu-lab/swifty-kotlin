inline fun myRepeat(times: Int, action: (Int) -> Unit) {
    var i = 0
    while (i < times) {
        action(i)
        i += 1
    }
}

fun find(): Int {
    myRepeat(10) { i -> if (i == 3) return i }
    return -1
}

fun labeled(): Int {
    myRepeat(10) { i -> if (i == 3) return@myRepeat }
    return 42
}

fun tailOnly(): Int {
    myRepeat(1) { it }
    return 42
}

fun main() {
    println(find())
    println(labeled())
    println(tailOnly())
}
