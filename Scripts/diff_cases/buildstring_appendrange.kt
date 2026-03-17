fun main() {
    val s = buildString {
        appendRange("Hello, World!", 0, 5)
        append(" ")
        appendRange("Hello, World!", 7, 13)
    }
    println(s)
}
