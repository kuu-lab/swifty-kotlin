fun main() {
    val list = listOf(1, 2, 3)
    val iterable: Iterable<Int> = list
    val array = arrayOf(1, 2, 3)

    try {
        list.windowed(0)
    } catch (e: IllegalArgumentException) {
        println("list-size")
    }
    try {
        list.windowed(2, step = 0)
    } catch (e: IllegalArgumentException) {
        println("list-step")
    }
    try {
        list.windowed(-1)
    } catch (e: IllegalArgumentException) {
        println("list-negative-size")
    }
    try {
        iterable.windowed(0)
    } catch (e: IllegalArgumentException) {
        println("iterable-size")
    }
    try {
        array.toList().windowed(2, step = 0)
    } catch (e: IllegalArgumentException) {
        println("array-backed-step")
    }
    try {
        list.windowed(0) { it.size }
    } catch (e: IllegalArgumentException) {
        println("transform-size")
    }
    try {
        list.windowed(2, step = 0) { it.size }
    } catch (e: IllegalArgumentException) {
        println("transform-step")
    }
}
