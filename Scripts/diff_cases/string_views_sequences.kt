fun main() {
    val text = "ab\ncd"
    val chars = "abc"
    val charSequence: CharSequence = chars

    var linesCount = 0
    for (line in text.lines()) {
        linesCount += 1
    }
    println(linesCount)

    println(text.lineSequence().toList().size)
    println(chars.asSequence().toList().size)
    chars.asIterable()
    chars.withIndex()
    charSequence.withIndex()
    println("views-ok")
}
