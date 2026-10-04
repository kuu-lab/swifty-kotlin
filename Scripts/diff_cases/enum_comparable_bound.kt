enum class Color { RED, GREEN, BLUE }

fun main() {
    println(listOf(Color.BLUE, Color.RED, Color.GREEN).sorted())
    println(listOf(Color.BLUE, Color.RED).sortedDescending())
    println(listOf(Color.BLUE, Color.RED).maxOrNull())
    println(maxOf(Color.RED, Color.BLUE))
    println(Color.RED < Color.BLUE)
}
