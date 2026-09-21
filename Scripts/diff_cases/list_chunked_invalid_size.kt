fun main() {
    val list = listOf(1, 2, 3)
    try {
        list.chunked(0)
        println("list-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("list-zero:ok")
    }
    try {
        list.chunked(-2)
        println("list-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("list-negative:ok")
    }

    val iterable: Iterable<Int> = list
    try {
        iterable.chunked(0)
        println("iterable-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("iterable-zero:ok")
    }
    try {
        iterable.chunked(-2)
        println("iterable-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("iterable-negative:ok")
    }

    val array: Iterable<Int> = arrayOf(1, 2, 3).toList()
    try {
        array.chunked(0)
        println("array-iterable-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("array-iterable-zero:ok")
    }
    try {
        array.chunked(-2)
        println("array-iterable-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("array-iterable-negative:ok")
    }

    try {
        list.chunked(0) { chunk -> chunk.sum() }
        println("transform-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("transform-zero:ok")
    }
    try {
        list.chunked(-2) { chunk -> chunk.sum() }
        println("transform-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("transform-negative:ok")
    }
}
