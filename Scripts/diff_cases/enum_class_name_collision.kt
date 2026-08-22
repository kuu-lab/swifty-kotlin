class Outer1 {
    enum class Color { RED, GREEN }
}

class Outer2 {
    enum class Color { RED, BLUE }
}

fun main() {
    println(Outer1.Color.RED.name)
    println(Outer2.Color.BLUE.name)
    println(Outer1.Color.valueOf("GREEN").name)
    println(Outer2.Color.valueOf("RED").name)

    val firstColors = Outer1.Color.values()
    val secondColors = Outer2.Color.values()
    println(firstColors.joinToString { it.name })
    println(secondColors.joinToString { it.name })

    println(listOf(Outer1.Color.GREEN).first().toString())
    println(listOf(Outer2.Color.RED).first().toString())
}
