fun main() {
    println(arrayOf(1, 2).joinToString())
    println(arrayOf("a", "b").joinToString("-"))

    val buffer = StringBuilder()
    arrayOf(1, 2).joinTo(buffer, ", ")
    println(buffer.toString())
}
