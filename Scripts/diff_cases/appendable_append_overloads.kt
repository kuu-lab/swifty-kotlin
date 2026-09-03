import kotlin.text.Appendable

fun main() {
    val sb = StringBuilder()
    val target: Appendable = sb
    target.append('a')
    target.append("bc")
    target.append("def", 1, 3)
    println(sb.toString())
}
