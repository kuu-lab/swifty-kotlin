private fun dumpLines(lines: List<String>) {
    println(lines.size)
    for (line in lines) {
        println("[$line]")
    }
    println("--")
}

fun main() {
    // String.lines() is covered separately by string_lines.kt.
    // Keep this case focused on lazy lineSequence materialization.
    dumpLines("a\nb\nc".lineSequence().toList())

    dumpLines("hello".lineSequence().toList())

    dumpLines("".lineSequence().toList())

    dumpLines("a\n\nb".lineSequence().toList())

    // Trailing newline
    dumpLines("a\nb\n".lineSequence().toList())

    // \r\n (Windows line endings)
    dumpLines("a\r\nb\r\nc".lineSequence().toList())

    // Mixed line endings
    dumpLines("a\nb\r\nc\rd".lineSequence().toList())

    // Only newlines
    dumpLines("\n".lineSequence().toList())
    dumpLines("\n\n".lineSequence().toList())
    dumpLines("\r\n".lineSequence().toList())

    // Single char
    dumpLines("x".lineSequence().toList())

    // lineSequence() size
    println("a\nb\nc".lineSequence().toList().size)

    // Edge cases for comprehensive testing
    // Multiple trailing newlines
    dumpLines("a\nb\n\n".lineSequence().toList())
    dumpLines("a\nb\n\r\n".lineSequence().toList())

    // Starting with newlines
    dumpLines("\na\nb".lineSequence().toList())
    dumpLines("\r\na\nb".lineSequence().toList())

    // Only carriage returns
    dumpLines("\r".lineSequence().toList())
    dumpLines("\r\r".lineSequence().toList())

    // Complex mixed patterns
    dumpLines("a\r\n\nb\r\nc\n\r".lineSequence().toList())

    // Whitespace handling
    dumpLines(" \n \t\n ".lineSequence().toList())

    // Unicode content with newlines
    dumpLines("こんにちは\n世界\n".lineSequence().toList())
}
