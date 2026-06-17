fun main() {
    val s = buildString {
        appendLine("hello")
        appendLine("world")
        appendLine('A')
        appendLine(true)
        appendLine(1.5f)
        appendLine(2.25)
        append("!")
    }
    println(s)
}
