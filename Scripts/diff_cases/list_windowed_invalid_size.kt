fun main() {
    val list = listOf(1, 2, 3, 4)
    try {
        list.windowed(0).toList()
        println("list-size-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("list-size-zero:ok")
    }
    try {
        list.windowed(-1).toList()
        println("list-size-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("list-size-negative:ok")
    }
    try {
        list.windowed(2, 0).toList()
        println("list-step-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("list-step-zero:ok")
    }
    try {
        list.windowed(2, -1).toList()
        println("list-step-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("list-step-negative:ok")
    }

    val iterable: Iterable<Int> = list
    try {
        iterable.windowed(0).toList()
        println("iterable-size-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("iterable-size-zero:ok")
    }
    try {
        iterable.windowed(2, 0).toList()
        println("iterable-step-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("iterable-step-zero:ok")
    }

    try {
        list.windowed(0) { window -> window.size }
        println("transform-size-zero:missing")
    } catch (e: IllegalArgumentException) {
        println("transform-size-zero:ok")
    }
}
