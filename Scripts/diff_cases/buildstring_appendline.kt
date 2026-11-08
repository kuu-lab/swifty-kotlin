// DIFF_JVM
fun main() {
    val s = buildString {
        appendLine("hello")
        appendLine("world")
        append("!")
    }
    println(s)
}
