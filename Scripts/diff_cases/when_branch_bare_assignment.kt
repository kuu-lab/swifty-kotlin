fun classify(c: Int): Int {
    val x: Int
    when (c) {
        1 -> x = 10
        2 -> { x = 20 }
        else -> throw IllegalStateException("unexpected: $c")
    }
    return x
}

var counter = 0
fun bump(c: Int) {
    when (c) {
        1 -> counter += 1
        else -> counter -= 1
    }
}

fun main() {
    println(classify(1))
    println(classify(2))
    bump(1)
    bump(2)
    println(counter)
}
