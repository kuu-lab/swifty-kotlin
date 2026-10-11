private var calls = 0

private fun nextText(): String {
    calls++
    return "BCDEFGHI"
}

fun main() {
    println(nextText().encodeToByteArray(4).decodeToString())
    println("calls:$calls")
    println("BCDEFGHI".encodeToByteArray(startIndex = 4).decodeToString())
    println("BCDEFGHI".encodeToByteArray(endIndex = 4).decodeToString())
    println("BCDEFGHI".encodeToByteArray(2, 6).decodeToString())
    println("BCDEFGHI".encodeToByteArray().decodeToString())
    println("BCDEFGHI".encodeToByteArray(startIndex = 8).size)
    println("".encodeToByteArray(startIndex = 0).size)
    println("".encodeToByteArray(endIndex = 0).size)
    println("Aé中Z".encodeToByteArray(1).decodeToString())
    println("Aé中Z".encodeToByteArray(endIndex = 3).decodeToString())
    println("A😀Z".encodeToByteArray(3).decodeToString())
    println("A😀Z".encodeToByteArray(endIndex = 3).decodeToString())
    try {
        "abc".encodeToByteArray(-1)
    } catch (e: IndexOutOfBoundsException) {
        println("negative-start")
    }
    try {
        "abc".encodeToByteArray(4)
    } catch (e: IllegalArgumentException) {
        println("past-end")
    }
    try {
        "abc".encodeToByteArray(endIndex = 4)
    } catch (e: IndexOutOfBoundsException) {
        println("invalid-end")
    }
    try {
        "abc".encodeToByteArray(2, 1)
    } catch (e: IllegalArgumentException) {
        println("reversed-range")
    }
    try {
        "abc".encodeToByteArray(endIndex = -1)
    } catch (e: IllegalArgumentException) {
        println("negative-end")
    }
    try {
        "abc".encodeToByteArray(5, 4)
    } catch (e: IndexOutOfBoundsException) {
        println("outside-before-reversed")
    }
    try {
        "abc".encodeToByteArray(-1, -2)
    } catch (e: IndexOutOfBoundsException) {
        println("negative-before-reversed")
    }
}
