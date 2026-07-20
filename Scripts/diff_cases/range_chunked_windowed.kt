fun main() {
    println((1..5).chunked(2))               // [[1, 2], [3, 4], [5]]
    println((1..5).windowed(3, 2, false))    // [[1, 2, 3], [3, 4, 5]]

    try {
        (1..5).chunked(0)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1..5).chunked(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1..5).windowed(0, 1, false)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1..5).windowed(2, 0, false)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1u..5u).chunked(0)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1u..5u).windowed(2, 0, false)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
