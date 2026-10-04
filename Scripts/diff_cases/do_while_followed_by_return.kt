fun countDown(start: Int): Int {
    var value = start
    while (value > 2)
        value -= 1
    do {
        value -= 1
    } while (value > 0)
    return value
}

fun unbracedBody(start: Int): Int {
    var value = start
    do value -= 1 while (value > 0)
    return value
}

fun main() {
    println(countDown(3))
    println(unbracedBody(2))
}
