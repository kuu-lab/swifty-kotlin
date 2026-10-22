// DIFF_JVM
enum class Color { RED, GREEN, BLUE }

fun main() {
    fun <T : Enum<T>> enumValueOf(name: String): String = "LOCAL:$name"
    println(enumValueOf<Color>("BLUE"))
}
