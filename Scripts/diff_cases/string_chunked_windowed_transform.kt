fun main() {
    println("abcdefg".chunked(3) { it.length })
    println("abcde".windowed(3, 2, true) { it.length })

    println("".chunked(3) { it.length })
    println("".windowed(3, 1, true) { it.length })

    println("hi".chunked(100) { it.length })
    println("hi".windowed(100, 1, true) { it.length })

    println("abcde".windowed(3, 2, false) { it.length })

    val chars: CharSequence = "abcdefg"
    println(chars.chunked(3) { it.length })
    println(chars.windowed(3, 2, true) { it.length })

    println("abcde".windowed(size = 3, step = 2, partialWindows = true) { window -> window.length })

    // Trailing lambda with defaulted middle parameters skipped
    // (kotlinc: step = 1, partialWindows = false).
    println("hello".windowed(2) { it.length })
    println("hello".windowed(3, 2) { it.length })
    println(chars.windowed(2) { it.length })
    println(chars.windowed(3, 2) { it.length })
    println("hello".windowedSequence(2) { it.length }.toList())
    println("hello".windowedSequence(3, 2) { it.length }.toList())
}
