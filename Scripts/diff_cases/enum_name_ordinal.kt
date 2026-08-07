enum class Color { RED, GREEN, BLUE }

fun describe(c: Color) {
    println(c.name)
    println(c.ordinal)
}

fun main() {
    println(Color.RED.name)
    println(Color.RED.ordinal)
    println(Color.GREEN.name)
    println(Color.GREEN.ordinal)

    // Dynamic (non-literal) enum receivers: a plain function parameter, a
    // collection HOF lambda parameter, and a lambda value bound to a
    // variable. These used to fail to link.
    describe(Color.BLUE)
    listOf(Color.RED, Color.GREEN, Color.BLUE).forEach { c -> println("${c.name}=${c.ordinal}") }
    val label: (Color) -> String = { c -> "${c.name}#${c.ordinal}" }
    println(label(Color.GREEN))
}
