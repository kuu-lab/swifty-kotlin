fun main() {
    val shortened = StringBuilder("abcde")
    val shortenedWindows = shortened.windowedSequence(3, 3, true) { it.toString() }
    shortened.setLength(3)
    println(shortenedWindows.toList())

    val extended = StringBuilder("ab")
    val extendedChunks = extended.chunkedSequence(5) { it.toString() }
    extended.append("cd")
    println(extendedChunks.toList())
}
