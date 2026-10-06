const val LF: Byte = 10

fun classify(b: Byte, n: Int): Int {
    when (b) {
        LF -> return 1
        13.toByte() -> if (n > 0) {
            return 2
        }
    }
    return 0
}

fun main() {
    println(classify(10, 3))
    println(classify(13, 3))
    println(classify(13, 0))
    println(classify(5, 0))
}
