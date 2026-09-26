fun viaIf(c: Boolean): Int {
    val x: Int
    if (c) {
        x = 1
    } else {
        return -1
    }
    return x
}

fun viaWhen(c: Int): Int {
    val x: Int
    when (c) {
        1 -> x = 10
        2 -> { x = 20 }
        else -> throw IllegalStateException()
    }
    return x
}

fun main() {
    println(viaIf(true))
    println(viaIf(false))
    println(viaWhen(1))
    println(viaWhen(2))
}
