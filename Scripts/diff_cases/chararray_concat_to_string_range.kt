fun main() {
    val chars = charArrayOf('a', 'b', 'c', 'd')
    println(chars.concatToString(1, 3))
    println(chars.concatToString(2, 2).isEmpty())
    println(chars.concatToString(0, chars.size))
    println(chars.concatToString())

    try {
        chars.concatToString(-1, 2)
    } catch (e: IndexOutOfBoundsException) {
        println("start out of bounds")
    }
    try {
        chars.concatToString(0, chars.size + 1)
    } catch (e: IndexOutOfBoundsException) {
        println("end out of bounds")
    }
    try {
        chars.concatToString(3, 2)
    } catch (e: IllegalArgumentException) {
        println("reversed range")
    }
}
