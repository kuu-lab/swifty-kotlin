fun takeString(value: String): String = value

fun main() {
    val empty: String = String()
    val typed = takeString(empty)
    println(typed == "")
    println(typed.length)
    println(typed + "x")
}
