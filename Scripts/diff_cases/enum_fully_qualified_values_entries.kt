enum class Color { RED, GREEN, BLUE }

fun main() {
    println(kotlin.enumValues<Color>().size)
    println(kotlin.enums.enumEntries<Color>().size)
}
